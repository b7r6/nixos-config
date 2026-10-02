;;; emacs-lsp-integration-tests.el --- Real language-server workflows -*- lexical-binding: t; -*-
(require 'ert)
(require 'lsp-mode)
(require 'flymake)
(require 'envrc)
(require 'lsp-yaml)
(require 'lsp-purescript)
(require 'lsp-pyright)

(defun hypermodern-lsp-test/write (root name contents)
  (let ((file (expand-file-name name root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert contents))
    file))

(defun hypermodern-lsp-test/wait (description predicate &optional seconds)
  (let ((deadline (+ (float-time) (or seconds 30))))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (unless (funcall predicate)
      (dolist (buffer (buffer-list))
        (when (string-match-p "stderr" (buffer-name buffer))
          (with-current-buffer buffer
            (message "%s: %s" (buffer-name) (buffer-substring-no-properties
                                            (max (point-min) (- (point-max) 4000)) (point-max))))))
      (ert-fail (format "Timed out: %s; diagnostics=%S" description
                        (mapcar #'flymake-diagnostic-text (flymake-diagnostics)))))))

(defconst hypermodern-lsp-test/cases
  '((nixd nix-ts-mode "sample.nix" "let answer = 42; in answer\n"
          "let answer = ; in answer\n" nil nil)
    (pyright python-ts-mode "sample.py" "answer: int = 42\n"
             "answer: int = 'wrong'\n" "answer" (("pyrightconfig.json" . "{\"typeCheckingMode\":\"strict\"}\n")))
    (clangd c-ts-mode "sample.c" "int answer(void) { return 42; }\n"
            "int answer(void) { return nonexistent; }\n" "answer" nil)
    (clangd c++-ts-mode "sample.cpp" "int answer() { return 42; }\n"
            "int answer() { return nonexistent; }\n" "answer" nil)
    (clangd cuda-mode "sample.cu" "int answer() { return 42; }\n"
            "int answer() { return nonexistent; }\n" "answer"
            (("compile_flags.txt" . "--cuda-host-only\n-nocudainc\n-nocudalib\n")))
    (ts-ls typescript-ts-mode "sample.ts" "export const answer: number = 42;\n"
           "export const answer: number = 'wrong';\n" "answer"
           (("tsconfig.json" . "{\"compilerOptions\":{\"strict\":true,\"noEmit\":true}}\n")))
    (ts-ls tsx-ts-mode "sample.tsx" "export const answer: number = 42;\nexport const node = <div />;\n"
           "export const answer: number = 'wrong';\nexport const node = <div />;\n" "answer"
           (("tsconfig.json" . "{\"compilerOptions\":{\"strict\":true,\"jsx\":\"preserve\",\"noEmit\":true}}\n")
            ("jsx.d.ts" . "declare namespace JSX { interface IntrinsicElements { div: {} } }\n")))
    (ts-ls js-ts-mode "sample.js" "// @ts-check\n/** @type {number} */\nexport const answer = 42;\n"
           "// @ts-check\n/** @type {number} */\nexport const answer = 'wrong';\n" "answer"
           (("jsconfig.json" . "{\"compilerOptions\":{\"checkJs\":true,\"noEmit\":true}}\n")))
    (json-ls json-ts-mode "sample.json" "{\"answer\": 42}\n" "{\"answer\": }\n" nil nil)
    (yamlls yaml-ts-mode "sample.yaml" "answer: 42\n" "answer: [1,\n" nil nil)
    (bash-ls bash-ts-mode "sample.sh" "#!/usr/bin/env bash\nanswer=42\necho \"$answer\"\n"
             "#!/usr/bin/env bash\necho $1\n" nil nil)
    (css-ls css-ts-mode "sample.css" "body { color: red; }\n" "body { color red; }\n" "color" nil)
    (html-ls html-ts-mode "sample.html" "<div>hello</div>\n" nil "div" nil)
    (taplo toml-ts-mode "sample.toml" "answer = 42\n" "answer = [\n" nil nil)
    (dhallls dhall-mode "sample.dhall" "let answer = 42 in answer\n"
              "let answer : Natural = True in answer\n" "answer" nil)
    (lean4-lsp lean4-mode "Sample.lean" "def answer : Nat := 42\n"
               "def answer : Nat := \"wrong\"\n" "answer" (("lakefile.toml" . "name = \"fixture\"\n")))
    (lsp-haskell haskell-mode "Sample.hs" "module Sample where\nanswer :: Int\nanswer = 42\n"
                 "module Sample where\nanswer :: Int\nanswer = \"wrong\"\n" "answer"
                 (("hie.yaml" . "cradle:\n  direct:\n    arguments: []\n")))
    (pursls purescript-mode "src/Sample.purs" "module Sample where\nanswer :: Int\nanswer = 42\n"
            "module Sample where\nanswer :: Int\nanswer = \"wrong\"\n" "answer" nil)
    (buck2 bazel-starlark-mode "sample.bzl" "def answer():\n    return 42\n"
           "def answer(:\n    return 42\n" nil
           ((".buckconfig" . "[cells]\nroot = .\n[buildfile]\nname = BUCK\n")))))

(defun hypermodern-lsp-test/workflow (case)
  (pcase-let* ((`(,client ,mode ,filename ,valid ,invalid ,hover ,files) case)
               (root (file-name-as-directory (make-temp-file "emacs-language-lsp-" t)))
               (default-directory root)
               (lsp-session-file (concat root "session"))
               (lsp-auto-guess-root nil)
               (lsp-enable-suggest-server-download nil)
               (lsp-keep-workspace-alive nil)
               (lsp-restart 'ignore)
               (lsp-enable-file-watchers nil)
               ;; Fixtures have no dependency downloads or schema catalogs.
               (lsp-yaml-schema-store-enable nil)
               (lsp-purescript-add-spago-sources nil)
               (buffer nil))
    (unwind-protect
        (progn
          (hypermodern-lsp-test/write root ".projectile" "")
          (dolist (file files) (hypermodern-lsp-test/write root (car file) (cdr file)))
          (when (and (eq client 'lean4-lsp) (getenv "EMACS_TEST_LEAN_TOOLCHAIN"))
            (hypermodern-lsp-test/write root "lean-toolchain" (getenv "EMACS_TEST_LEAN_TOOLCHAIN")))
          (hypermodern-lsp-test/write root filename valid)
          (when (eq client 'pursls)
            (should (zerop (call-process "purs" nil "*purs-test-build*" nil "compile" "src/Sample.purs"))))
          (lsp-workspace-folders-add root)
          (setq buffer (find-file-noselect (expand-file-name filename root)))
          (with-current-buffer buffer
            (funcall mode)
            ;; Batch has no idle command loop; startup/restart run synchronously.
            (setq-local lsp--buffer-deferred nil)
            (lsp)
            (hypermodern-lsp-test/wait
             (format "%s initialized" client)
             (lambda () (seq-some (lambda (ws) (eq (lsp--workspace-status ws) 'initialized))
                                  (lsp-workspaces))))
            (should (eq client (lsp--client-server-id (lsp--workspace-client (car (lsp-workspaces))))))
            (should (equal (directory-file-name root) (lsp--workspace-root (car (lsp-workspaces)))))
            (hypermodern-lsp-test/wait
             (format "%s completion registration" client)
             (lambda () (memq 'lsp-completion-at-point completion-at-point-functions)))
            (when-let* ((probe (assq client '((css-ls "body { col }" "col" "color")
                                               (html-ls "<di" "di" "div")
                                               (json-ls "{\"$sch" "$sch" "$schema")))))
              (erase-buffer) (insert (nth 1 probe))
              (search-backward (nth 2 probe)) (forward-char (length (nth 2 probe)))
              (let* ((capf (lsp-completion-at-point))
                     (candidates (all-completions (nth 2 probe) (nth 2 capf))))
                (should (member (nth 3 probe) candidates)))
              (erase-buffer) (insert valid))
            (when hover
              (hypermodern-lsp-test/wait
               (format "%s hover" client)
               (lambda ()
                 (goto-char (point-min)) (search-forward hover) (backward-char)
                 (lsp-request "textDocument/hover" (lsp--text-document-position-params)))))
            (when (eq client 'nixd)
              ;; Nixd's hover targets configured package/option idioms. Exercise
              ;; dependency-free local navigation instead of requiring nixpkgs.
              (goto-char (point-max)) (search-backward "answer")
              (hypermodern-lsp-test/wait
               "Nix definition"
               (lambda () (lsp-request "textDocument/definition" (lsp--text-document-position-params)))))
            (when invalid
              (erase-buffer) (insert invalid)
              ;; Write without invoking a formatter on deliberately broken syntax.
              ;; save-buffer still sends didSave for servers which check on save.
              (let ((before-save-hook nil)) (save-buffer))
              (flymake-start)
              (hypermodern-lsp-test/wait
               (format "%s diagnostics" client) (lambda () (flymake-diagnostics)))
              (should (memq 'lsp-diagnostics--flymake-backend flymake-diagnostic-functions))
              (dolist (native (plist-get (cdr (hypermodern/language-entry)) :native-checkers))
                (should-not (memq native flymake-diagnostic-functions)))
              (erase-buffer) (insert valid)
              (let ((before-save-hook nil)) (save-buffer))
              (flymake-start)
              (hypermodern-lsp-test/wait
               (format "%s diagnostic repair" client) (lambda () (null (flymake-diagnostics)))))
            (message "PASS actual %s / %s: attachment, project root, CAPF%s%s"
                     client mode (if hover ", hover" "")
                     (if invalid ", Flymake diagnostics and repair" ""))))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (dolist (workspace (lsp-workspaces)) (ignore-errors (lsp-workspace-shutdown workspace)))
          (set-buffer-modified-p nil))
        (kill-buffer buffer))
      (when (eq client 'buck2) (call-process "buck2" nil nil nil "kill"))
      (delete-directory root t))))

(dolist (case hypermodern-lsp-test/cases)
  (eval `(ert-deftest ,(intern (format "hypermodern/real-lsp-%s-%s" (car case) (cadr case))) ()
           (hypermodern-lsp-test/workflow ',case)) t))


(ert-deftest hypermodern/python-project-environments-and-restart ()
  "Two projects get separate direnv servers; restart preserves unsaved text."
  (let* ((root (file-name-as-directory (make-temp-file "emacs-python-env-" t)))
         (default-directory root)
         (process-environment (copy-sequence process-environment))
         (lsp-session-file (concat root "session"))
         (lsp-auto-guess-root nil)
         (lsp-enable-suggest-server-download nil)
         (lsp-keep-workspace-alive nil)
         (lsp-restart 'ignore)
         (server (executable-find "pyright-langserver"))
         buffers workspaces)
    (setenv "DIRENV_DIFF" nil)
    (setenv "DIRENV_DIR" nil)
    (setenv "XDG_CONFIG_HOME" (concat root "config"))
    (setenv "XDG_DATA_HOME" (concat root "data"))
    (unwind-protect
        (progn
          (dolist (name '("one" "two"))
            (let ((project (concat root name "/")))
              (hypermodern-lsp-test/write project ".projectile" "")
              (hypermodern-lsp-test/write project "pyrightconfig.json" "{\"typeCheckingMode\":\"strict\"}")
              (hypermodern-lsp-test/write project "main.py" "answer: int = 42\n")
              (hypermodern-lsp-test/write
               project "bin/pyright-langserver"
               (format "#!%s\nprintf '%%s\\n' \"$EMACS_PYRIGHT_TEST\" >> %s\nexec %s \"$@\"\n"
                       (executable-find "sh")
                       (shell-quote-argument (concat project "launches"))
                       (shell-quote-argument server)))
              (set-file-modes (concat project "bin/pyright-langserver") #o755)
              (hypermodern-lsp-test/write project ".envrc"
                                         (format "PATH_add bin\nexport EMACS_PYRIGHT_TEST=%s\n" name))
              (should (zerop (call-process "direnv" nil nil nil "allow" project)))
              (lsp-workspace-folders-add project)
              (let ((buffer (find-file-noselect (concat project "main.py"))))
                (push buffer buffers)
                (with-current-buffer buffer
                  (setq-local lsp--buffer-deferred nil)
                  (lsp)
                  (hypermodern-lsp-test/wait
                   "project connected" (lambda () (bound-and-true-p lsp-managed-mode)))
                  (push (car (lsp-workspaces)) workspaces)
                  (should (equal (getenv "EMACS_PYRIGHT_TEST") name))
                  (should (equal (lsp--workspace-root (car workspaces)) (directory-file-name project)))
                  (should (equal (with-temp-buffer
                                   (insert-file-contents (concat project "launches")) (buffer-string))
                                 (concat name "\n")))))))
          (should-not (eq (car workspaces) (cadr workspaces)))
          (should-not (eq (lsp--workspace-proc (car workspaces))
                          (lsp--workspace-proc (cadr workspaces))))
          (with-current-buffer (car buffers)
            (goto-char (point-max)) (insert "# unsaved through restart\n")
            (let ((unsaved (buffer-string))
                  (old-process (lsp--workspace-proc (car workspaces)))
                  (other-process (lsp--workspace-proc (cadr workspaces))))
              (hypermodern-lsp-test/write (concat root "two/") ".envrc"
                                         "PATH_add bin\nexport EMACS_PYRIGHT_TEST=restarted\n")
              (should (zerop (call-process "direnv" nil nil nil "allow" (concat root "two/"))))
              (envrc-reload)
              (lsp-workspace-restart (car workspaces))
              (hypermodern-lsp-test/wait
               "restarted project initialized"
               (lambda () (and (bound-and-true-p lsp-managed-mode)
                               (lsp-workspaces)
                               (eq (lsp--workspace-status (car (lsp-workspaces))) 'initialized)
                               (not (eq old-process (lsp--workspace-proc (car (lsp-workspaces))))))))
              (should (equal (buffer-string) unsaved))
              (should (buffer-modified-p))
              (should (process-live-p other-process))
              (should (with-temp-buffer
                        (insert-file-contents (concat root "two/launches"))
                        (equal (buffer-string) "two\nrestarted\n")))
              (goto-char (point-min)) (search-forward "answer") (backward-char)
              (hypermodern-lsp-test/wait
               "hover after restart"
               (lambda () (lsp-request "textDocument/hover" (lsp--text-document-position-params))))))
          (message "PASS: two real Pyright projects, isolated direnv launchers, restart with fresh environment and unsaved text"))
      (dolist (buffer buffers)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (dolist (workspace (lsp-workspaces)) (ignore-errors (lsp-workspace-shutdown workspace)))
            (set-buffer-modified-p nil))
          (kill-buffer buffer)))
      (delete-directory root t))))

;;; emacs-lsp-integration-tests.el ends here
