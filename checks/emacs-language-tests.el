;;; emacs-language-tests.el --- Language routing and real formatters -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'lsp-mode)
(require 'format-all)
(require 'flymake)
(require 'lsp-diagnostics)
(dolist (library '(nix-mode nix-ts-mode haskell-mode rust-mode rust-ts-mode
                   python cc-mode c-ts-mode cuda-mode typescript-mode typescript-ts-mode
                   js json-mode json-ts-mode yaml-mode yaml-ts-mode sh-script
                   purescript-mode lean4-mode bazel dhall-mode markdown-mode
                   css-mode sgml-mode html-ts-mode toml-ts-mode))
  (require library))
(lsp--require-packages)

(ert-deftest hypermodern/language-mode-matrix ()
  "Every configured concrete mode starts its intended client exactly once."
  (let* ((root (make-temp-file "emacs-modes-" t))
         (default-directory (file-name-as-directory root))
         (rust-mode-treesitter-derive nil))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name ".buckconfig" root) (insert "[cells]\nroot = .\n"))
          (dolist (entry hypermodern/language-registry)
            (let ((config (cdr entry)))
              (dolist (mode (cons (plist-get config :mode) (plist-get config :extra-modes)))
                (ert-info ((format "Language %s, mode %s" (car entry) mode))
                  (with-temp-buffer
                    (setq buffer-file-name
                          (expand-file-name (if (eq mode 'tsx-ts-mode) "example.tsx" "example") root))
                    (let ((starts 0))
                      (cl-letf (((symbol-function 'lsp-deferred) (lambda () (cl-incf starts))))
                        (funcall mode))
                      (should (eq (car (hypermodern/language-entry)) (car entry)))
                      (should (= starts (if (eq (plist-get config :backend) 'lsp) 1 0)))
                      (when (eq (plist-get config :backend) 'lsp)
                        (let ((client (gethash (plist-get config :client) lsp-clients)))
                          (should client)
                          (should (lsp--supports-buffer? client))))
                      (if (eq (car entry) 'rust)
                          (should-not format-all-mode)
                        (when-let* ((formatter (plist-get config :format-all-formatter)))
                          (should format-all-mode)
                          (should (eq formatter (caar (format-all--normalize-chain
                                                      (format-all--get-chain
                                                       (format-all--language-id-buffer)))))))))
                    ;; Check diagnostics ownership after attachment, retaining
                    ;; unrelated/complementary backends rather than clearing all.
                    (let ((native (plist-get config :native-checkers)))
                      (setq-local flymake-diagnostic-functions (append native '(complementary-check)))
                      (setq-local lsp-managed-mode t)
                      (run-hooks 'lsp-managed-mode-hook)
                      (should (equal flymake-diagnostic-functions '(complementary-check))))))))))
      (delete-directory root t))))

(ert-deftest hypermodern/language-startup-boundaries ()
  "Fontification buffers and non-Buck Starlark must not start servers."
  (dolist (mode '(python-mode js-mode lean4-mode bazel-starlark-mode))
    (with-temp-buffer
      (let ((default-directory temporary-file-directory))
        (when (eq mode 'bazel-starlark-mode)
          (setq buffer-file-name (expand-file-name "ordinary.bzl" temporary-file-directory)))
        (cl-letf (((symbol-function 'lsp-deferred)
                   (lambda () (ert-fail "Unexpected language server startup"))))
          (funcall mode)))))
  (with-temp-buffer
    (python-mode)
    (should (memq 'python-flymake flymake-diagnostic-functions))
    (setq-local lsp-managed-mode nil)
    (hypermodern/language-diagnostics-setup)
    (should (memq 'python-flymake flymake-diagnostic-functions)))
  (should-not (lsp--client-multi-root (gethash 'pyright lsp-clients))))

(defconst hypermodern-test/format-cases
  '((nix-mode "sample.nix" "{a=1;b=[1 2];}\n")
    (haskell-mode "Example.hs" "module Example where\nanswer=42\n")
    (python-mode "sample.py" "def example( a,b ):\n return {\"a\":a,\"b\":b}\n")
    (c-mode "sample.c" "int example(int x){return x+1;}\n")
    (c++-mode "sample.cpp" "int example(int x){return x+1;}\n")
    (cuda-mode "sample.cu" "int example(int x){return x+1;}\n")
    (typescript-ts-mode "sample.ts" "export const answer:number=42\n")
    (tsx-ts-mode "sample.tsx" "export const node=<div id=\"x\">hi</div>\n")
    (js-ts-mode "sample.js" "export const answer={a:1,b:2}\n")
    (json-ts-mode "sample.json" "{\"a\":1,\"b\":[2,3]}\n")
    (yaml-ts-mode "sample.yaml" "answer:  [1,2]\n")
    (bash-ts-mode "sample.sh" "#!/usr/bin/env bash\nif true;then\necho hi\nfi\n")
    (purescript-mode "Example.purs" "module Example where\nanswer=42\n")
    (bazel-starlark-mode "sample.bzl" "def example(x):\n  return {\"a\":x}\n")
    (bazel-starlark-mode "BUCK" "example(name=\"hi\",srcs=[\"a\",\"b\"])\n")
    (dhall-mode "sample.dhall" "let x=1 in {a=x,b=2}\n")
    (css-ts-mode "sample.css" "body{color:red;background:white}\n")
    (html-ts-mode "sample.html" "<html><body><div>hi</div></body></html>\n")
    (toml-ts-mode "sample.toml" "answer=42\nvalues=[1,2,3]\n")
    (markdown-mode "sample.md" "# Hi\n\n-   one\n-   two\n")
    (emacs-lisp-mode "sample.el" "(let ((x 1))\n(+ x 2))\n")))

(ert-deftest hypermodern/real-formatter-matrix ()
  "Manual and on-save formatting use real tools, respect project config, and settle."
  (let* ((root (make-temp-file "emacs-formatters-" t))
         (default-directory (file-name-as-directory root)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name ".projectile" root))
          (with-temp-file (expand-file-name "pyproject.toml" root)
            (insert "[tool.ruff.format]\nquote-style = 'single'\n"))
          (with-temp-file (expand-file-name ".prettierrc.json" root)
            (insert "{\"semi\":false,\"singleQuote\":true}\n"))
          (dolist (case hypermodern-test/format-cases)
            (pcase-let ((`(,mode ,filename ,original) case))
              (ert-info ((format "Real formatter %s" filename))
                (with-temp-buffer
                  (setq buffer-file-name (expand-file-name filename root))
                  (cl-letf (((symbol-function 'lsp-deferred) #'ignore)) (funcall mode))
                  (insert original)
                  (hypermodern/format-buffer)
                  (let ((formatted (buffer-string)))
                    (should-not (equal original formatted))
                    (hypermodern/format-buffer)
                    (should (equal formatted (buffer-string)))
                    (erase-buffer) (insert original)
                    (save-buffer)
                    (should (equal formatted (buffer-string)))
                    (should (equal formatted (with-temp-buffer
                                               (insert-file-contents (expand-file-name filename root))
                                               (buffer-string)))))
                  (when (eq mode 'python-mode)
                    (should (string-match-p "'a':" (buffer-string)))))))))
      (delete-directory root t))))

(ert-deftest hypermodern/ruff-invalid-input-is-visible ()
  "Ruff parse failures preserve unsaved text and show the actual error."
  (with-temp-buffer
    (setq buffer-file-name (expand-file-name "broken.py" temporary-file-directory))
    (cl-letf (((symbol-function 'lsp-deferred) #'ignore)) (python-mode))
    (insert "def broken(:\n")
    (hypermodern/format-buffer)
    (should (equal (buffer-string) "def broken(:\n"))
    (should (with-current-buffer "*format-all-errors*"
              (string-match-p "Failed to parse" (buffer-string))))))

(ert-deftest hypermodern/missing-formatter-does-not-block-save ()
  "Manual errors remain visible; save still writes the user's unformatted text."
  (let* ((root (make-temp-file "emacs-missing-formatter-" t))
         (default-directory (file-name-as-directory root)))
    (unwind-protect
        (with-temp-buffer
          (setq buffer-file-name (expand-file-name "sample.py" root))
          (cl-letf (((symbol-function 'lsp-deferred) #'ignore)) (python-mode))
          (insert "answer=42\n")
          (let ((exec-path nil))
            (should-error (hypermodern/format-buffer) :type 'format-all-executable-not-found)
            (save-buffer))
          (should (equal (buffer-string) "answer=42\n"))
          (should (file-exists-p buffer-file-name)))
      (delete-directory root t))))


(ert-deftest hypermodern/lean-progress-timer-lifetime ()
  "Closing/reusing a Lean buffer cancels its redraw without touching other buffers."
  (let ((first (generate-new-buffer " *lean-first*"))
        (second (generate-new-buffer " *lean-second*"))
        timers)
    (unwind-protect
        (progn
          (dolist (buffer (list first second))
            (with-current-buffer buffer
              (lean4-mode)
              (setq lean4-fringe-delay-timer (run-at-time 60 nil #'ignore))
              (push lean4-fringe-delay-timer timers)))
          (kill-buffer first)
          (should-not (memq (cadr timers) timer-list))
          (should (memq (car timers) timer-list))
          (with-current-buffer second (fundamental-mode))
          (should-not (memq (car timers) timer-list)))
      (mapc #'cancel-timer timers)
      (when (buffer-live-p first) (kill-buffer first))
      (when (buffer-live-p second) (kill-buffer second)))))

(ert-deftest hypermodern/lsp-diagnostics-survive-capability-registration ()
  "Repeated setup must not sever an enabled Flymake backend's callback."
  (with-temp-buffer
    (setq buffer-file-name (expand-file-name "diagnostics.py" temporary-file-directory))
    (insert "answer\n")
    (setq-local flymake-diagnostic-functions nil)
    (lsp-diagnostics--flymake-setup)
    (flymake-start)
    (let* ((reporter lsp-diagnostics--flymake-report-fn)
           (diagnostics (make-hash-table :test 'equal)))
      (should (functionp reporter))
      ;; Same path used when a server dynamically registers formatting or other
      ;; capabilities after initial attachment. No sleeps or timing assumptions.
      (lsp-diagnostics--flymake-setup)
      (should (eq reporter lsp-diagnostics--flymake-report-fn))
      (puthash buffer-file-name
               (list (lsp-make-diagnostic
                      :range (lsp-make-range :start (lsp-make-position :line 0 :character 0)
                                             :end (lsp-make-position :line 0 :character 6))
                      :message "an actual diagnostic" :severity 1)) diagnostics)
      (cl-letf (((symbol-function 'lsp-diagnostics) (lambda (&rest _) diagnostics)))
        (run-hooks 'lsp-diagnostics-updated-hook))
      (should (equal (mapcar #'flymake-diagnostic-text (flymake-diagnostics))
                     '("an actual diagnostic")))
      ;; A disabled/restarted checker must acquire a fresh callback, never retain
      ;; the report token from its previous lifetime.
      (flymake-mode -1)
      (lsp-diagnostics--flymake-setup)
      (flymake-start)
      (should (functionp lsp-diagnostics--flymake-report-fn))
      (should-not (eq reporter lsp-diagnostics--flymake-report-fn)))))

;;; emacs-language-tests.el ends here
