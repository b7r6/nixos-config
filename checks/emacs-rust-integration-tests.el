;;; emacs-rust-integration-tests.el --- Real Rust LSP workflows -*- lexical-binding: t; -*-

;; Run after the production init, with package autoloads enabled. Everything
;; written or compiled belongs to a temporary, dependency-free Cargo workspace.
(require 'ert)
(require 'lsp-mode)
(require 'lsp-rust)
(require 'envrc)
(require 'flymake)
(require 'rust-mode)
(require 'rust-ts-mode)

(defun hypermodern-test/write (root path contents)
  (let ((file (expand-file-name path root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert contents))
    file))

(defun hypermodern-test/wait (description predicate &optional seconds)
  "Wait for a protocol condition, not an assumed workspace-loading delay."
  (let ((deadline (+ (float-time) (or seconds 45))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (unless (funcall predicate)
      (message "At timeout, buffer: %s; diagnostics: %S" (buffer-name)
               (and (bound-and-true-p flymake-mode)
                    (mapcar #'flymake-diagnostic-text (flymake-diagnostics))))
      (when (string-match-p "expansion" description)
        (message "Generated function hover: %S; build-script function hover: %S"
                 (hypermodern-test/hover "generated()") (hypermodern-test/hover "from_build()"))
        (save-excursion
          (hypermodern-test/at "include")
          (message "Include expansion: %S"
                   (lsp-request "rust-analyzer/expandMacro" (lsp--text-document-position-params)))))
      (dolist (b (buffer-list))
        (when (string-match-p "rust-analyzer.*stderr" (buffer-name b))
          (with-current-buffer b (message "Server stderr: %s" (buffer-string)))))
      (ert-fail (concat "Timed out: " description)))))

(defun hypermodern-test/at (text)
  (goto-char (point-min))
  (search-forward text)
  (backward-char (if (string-suffix-p "()" text) 3 1)))

(defun hypermodern-test/hover (text)
  (save-excursion
    (hypermodern-test/at text)
    (lsp-request "textDocument/hover" (lsp--text-document-position-params))))

(defun hypermodern-test/contents (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest hypermodern/rust-real-workflows ()
  "Exercise the actual client/server, including failure and reconnection."
  (let* ((root (file-name-as-directory (make-temp-file "emacs-rust-lsp-" t)))
         (default-directory root)
         (process-environment (copy-sequence process-environment))
         (lsp-session-file (concat root "session"))
         (lsp-auto-guess-root nil)
         (lsp-enable-suggest-server-download nil)
         (lsp-keep-workspace-alive nil)
         (lsp-restart 'ignore)
         (rust-mode-treesitter-derive nil)
         (real-analyzer (executable-find "rust-analyzer"))
         (modern-text "macros::answer!();\ninclude!(concat!(env!(\"OUT_DIR\"), \"/generated.rs\"));\npub async fn example(){let x=1;println!(\"{x}\");}\npub fn probe()->u32{generated()+from_build()}\n")
         (legacy-text "pub fn async(){let x=1;println!(\"{}\",x);}\n")
         buffers workspace)
    (setenv "DIRENV_DIFF" nil)
    (setenv "DIRENV_DIR" nil)
    (setenv "CARGO_NET_OFFLINE" "true")
    (setenv "CARGO_TARGET_DIR" (concat root "target"))
    (setenv "XDG_CONFIG_HOME" (concat root "config"))
    (setenv "XDG_DATA_HOME" (concat root "data"))
    (when-let* ((src (getenv "EMACS_TEST_RUST_SRC")))
      (setq lsp-rust-analyzer-cargo-sysroot-src src))
    (unwind-protect
        (progn
          (hypermodern-test/write root ".projectile" "")
          (hypermodern-test/write root "Cargo.toml"
                                 "[workspace]\nmembers=[\"modern\",\"legacy\",\"macros\"]\nresolver=\"2\"\n[workspace.package]\nedition=\"2024\"\n")
          (hypermodern-test/write root "modern/Cargo.toml"
                                 "[package]\nname=\"modern\"\nversion=\"0.1.0\"\nedition.workspace=true\n[dependencies]\nmacros={path=\"../macros\"}\n")
          (hypermodern-test/write root "legacy/Cargo.toml"
                                 "[package]\nname=\"legacy\"\nversion=\"0.1.0\"\nedition=\"2015\"\n")
          (hypermodern-test/write root "macros/Cargo.toml"
                                 "[package]\nname=\"macros\"\nversion=\"0.1.0\"\nedition=\"2024\"\n[lib]\nproc-macro=true\n")
          (hypermodern-test/write root "macros/src/lib.rs"
                                 "use proc_macro::TokenStream;\n#[proc_macro]\npub fn answer(_:TokenStream)->TokenStream { \"pub fn generated()->u32 {42}\".parse().unwrap() }\n")
          (hypermodern-test/write root "modern/build.rs"
                                 "fn main(){let out=std::env::var(\"OUT_DIR\").unwrap();std::fs::write(std::path::Path::new(&out).join(\"generated.rs\"),\"pub fn from_build()->u32 {7}\\n\").unwrap();}\n")
          (hypermodern-test/write root "modern/src/lib.rs" modern-text)
          (hypermodern-test/write root "legacy/src/lib.rs" legacy-text)
          ;; A project-local launcher records only our test marker. This checks
          ;; the real envrc -> server startup ordering, without mocking either.
          (hypermodern-test/write root "bin/rust-analyzer"
                                 (format "#!%s\nprintf '%%s\\n' \"$EMACS_RUST_TEST_ENV\" >> %s\nexec %s \"$@\"\n"
                                         (executable-find "sh")
                                         (shell-quote-argument (concat root "launches"))
                                         (shell-quote-argument real-analyzer)))
          (set-file-modes (concat root "bin/rust-analyzer") #o755)
          (hypermodern-test/write root ".envrc" "PATH_add bin\nexport EMACS_RUST_TEST_ENV=first\n")
          (should (zerop (call-process "direnv" nil nil nil "allow" root)))
          (lsp-workspace-folders-add root)
          (dolist (case '(("modern" rust-ts-mode) ("legacy" rust-mode)))
            (let* ((file (concat root (car case) "/src/lib.rs"))
                   (buffer (find-file-noselect file)))
              (push buffer buffers)
              (with-current-buffer buffer
                (funcall (cadr case))
                ;; Batch has no idle command loop; attach synchronously, including
                ;; on restart. The actual mode/envrc hooks have already run.
                (setq-local lsp--buffer-deferred nil)
                (lsp)
                (hypermodern-test/wait "workspace ready" #'hypermodern/rust-ready-p)
                (should (equal (lsp--workspace-root (car (lsp-workspaces)))
                               (directory-file-name root)))
                (if workspace
                    (should (eq workspace (car (lsp-workspaces))))
                  (setq workspace (car (lsp-workspaces))))
                (should (eq lsp-diagnostics-provider :flymake))
                (should flymake-mode)
                (should (memq 'lsp-diagnostics--flymake-backend flymake-diagnostic-functions))
                (should-not (memq 'rust-ts-flymake flymake-diagnostic-functions))
                (should (memq 'lsp-completion-at-point completion-at-point-functions))
                (should-not format-all-mode)
                (let ((original (buffer-string)))
                  (hypermodern/format-buffer)
                  (should-not (equal original (buffer-string)))
                  (let ((formatted (buffer-string)))
                    (hypermodern/format-buffer)
                    (should (equal formatted (buffer-string))))
                  ;; A real save exercises both formatting and didSave checking.
                  (erase-buffer) (insert original)
                  (save-buffer)
                  (should-not (equal original (hypermodern-test/contents file)))))))
          (should (equal (hypermodern-test/contents (concat root "launches")) "first\n"))
          (with-current-buffer (cadr buffers) ; modern was opened first
            (hypermodern-test/wait
             "proc macro and build script expansion"
             (lambda ()
               (and (hypermodern-test/hover "generated()")
                    (hypermodern-test/hover "from_build()"))))
            ;; Completion must traverse the actual CAPF used by company.
            (goto-char (point-max))
            (insert "pub fn completion_probe() { genera }\n")
            (search-backward "genera") (forward-char 6)
            (let* ((capf (lsp-completion-at-point))
                   (candidates (all-completions "genera" (nth 2 capf))))
              (should (seq-some (lambda (s) (string-prefix-p "generated" s)) candidates)))
            (erase-buffer) (insert modern-text)
            (hypermodern-test/at "from_build()")
            (should (lsp-request "textDocument/definition" (lsp--text-document-position-params)))
            ;; rust-analyzer returns null on invalid syntax; preserve the text
            ;; and verify that the syntax error is visible through diagnostics.
            (let ((valid (buffer-string)))
              (erase-buffer) (insert "pub fn broken( {\n")
              (hypermodern/format-buffer)
              (should (equal (buffer-string) "pub fn broken( {\n"))
              (flymake-start)
              (hypermodern-test/wait "syntax diagnostics"
                                    (lambda () (flymake-diagnostics)))
              (erase-buffer) (insert valid))
            ;; A compiler type error must reach Flymake, then disappear on repair.
            (goto-char (point-max)) (insert "pub fn wrong() -> u32 { \"wrong\" }\n")
            (save-buffer)
            (flymake-start)
            (hypermodern-test/wait
             "compiler diagnostics in Flymake"
             (lambda () (seq-some (lambda (d) (string-match-p "mismatched types" (flymake-diagnostic-text d)))
                                 (flymake-diagnostics))))
            (erase-buffer) (insert modern-text) (save-buffer) (flymake-start)
            (hypermodern-test/wait "diagnostics cleared after fix"
                                  (lambda () (null (flymake-diagnostics))))
            ;; Cargo workspace reload must leave formatting and navigation usable.
            (let ((before (gethash workspace hypermodern/rust-server-status)))
              (lsp-request "rust-analyzer/reloadWorkspace" nil)
              (hypermodern-test/wait
               "reload settled"
               (lambda () (and (not (eq before (gethash workspace hypermodern/rust-server-status)))
                               (hypermodern/rust-ready-p)))))
            (should (hypermodern-test/hover "from_build()"))
            ;; Retain unsaved text across a real server restart; reread direnv so
            ;; the replacement process also sees an updated project environment.
            (goto-char (point-max)) (insert "// unsaved through restart\n")
            (let ((unsaved (buffer-string))
                  (old-process (lsp--workspace-proc workspace)))
              (hypermodern-test/write root ".envrc" "PATH_add bin\nexport EMACS_RUST_TEST_ENV=second\n")
              (should (zerop (call-process "direnv" nil nil nil "allow" root)))
              (envrc-reload)
              (lsp-workspace-restart workspace)
              (hypermodern-test/wait
               "server restarted with fresh environment"
               (lambda () (and (hypermodern/rust-ready-p)
                               (not (eq old-process (lsp--workspace-proc (car (lsp-workspaces))))))))
              (should (equal unsaved (buffer-string)))
              (should (buffer-modified-p))
              (should (string-suffix-p "second\n" (hypermodern-test/contents (concat root "launches"))))
              (hypermodern/format-buffer)
              (should (string-match-p "unsaved through restart" (buffer-string)))
              (should (hypermodern-test/hover "generated()"))
              ;; Simulate an actual crash, then use the normal reconnect command.
              (delete-process (lsp--workspace-proc (car (lsp-workspaces))))
              (hypermodern-test/wait "dead server detached" (lambda () (null (lsp-workspaces))))
              (should-error (hypermodern/format-buffer) :type 'user-error)
              (lsp)
              (hypermodern-test/wait "reconnected after crash" #'hypermodern/rust-ready-p)
              (should (equal unsaved (buffer-string)))
              (should (hypermodern-test/hover "generated()"))))
          (message "PASS: editions, envrc, formatting/save/invalid syntax, CAPF, hover/definition, macros/build scripts, Flymake repair, reload, restart and crash recovery with unsaved text"))
      (let (workspaces)
        (dolist (buffer buffers)
          (when (buffer-live-p buffer)
            (with-current-buffer buffer
              (setq workspaces (append (lsp-workspaces) workspaces)))))
        (dolist (ws (delete-dups workspaces))
          (ignore-errors (lsp-workspace-shutdown ws))))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory root t))))

;;; emacs-rust-integration-tests.el ends here
