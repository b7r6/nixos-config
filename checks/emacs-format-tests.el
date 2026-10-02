;;; emacs-format-tests.el --- Runtime formatter routing checks -*- lexical-binding: t; -*-

;; Run after the real init.el. Do not launch language servers or write user files.
(require 'ert)
(require 'cl-lib)
(require 'lsp-mode)
(require 'format-all)
(require 'rust-mode)
(require 'rust-ts-mode)

(ert-deftest hypermodern/rust-format-manual-and-save ()
  "Both Rust modes must use the connected server, never bare rustfmt."
  (dolist (mode '(rust-mode rust-ts-mode))
    (with-temp-buffer
      (let ((calls 0)
            ;; Exercise rust-mode itself even on hosts with its ts remap enabled.
            (rust-mode-treesitter-derive nil))
        (cl-letf (((symbol-function 'lsp-deferred) #'ignore)
                  ((symbol-function 'lsp-feature?) (lambda (_) t))
                  ((symbol-function 'lsp-format-buffer)
                   (lambda () (cl-incf calls)))
                  ((symbol-function 'format-all-buffer)
                   (lambda (&rest _) (ert-fail "Rust reached format-all"))))
          (funcall mode)
          (setq-local lsp-mode t)
          (should-not format-all-mode)
          (should-not (memq 'format-all--buffer-from-hook before-save-hook))
          (hypermodern/format-buffer)
          (run-hooks 'before-save-hook)
          (should (= calls 2)))))))

(ert-deftest hypermodern/rust-format-disconnected ()
  "M-z explains a missing server; an ordinary save remains possible."
  (with-temp-buffer
    (let ((rust-mode-treesitter-derive nil))
      (cl-letf (((symbol-function 'lsp-deferred) #'ignore))
        (rust-mode)))
    (setq-local lsp-mode nil)
    (let ((err (should-error (hypermodern/format-buffer) :type 'user-error)))
      (should (string-match-p "rust-analyzer" (error-message-string err))))
    (let (reported)
      (cl-letf (((symbol-function 'message)
                 (lambda (fmt &rest args) (setq reported (apply #'format fmt args)))))
        (run-hooks 'before-save-hook))
      (should (string-match-p "Rust formatting skipped" reported)))))

(ert-deftest hypermodern/rust-format-server-failure ()
  "Do not swallow a server's formatting error when formatting explicitly."
  (with-temp-buffer
    (let ((rust-mode-treesitter-derive nil))
      (cl-letf (((symbol-function 'lsp-deferred) #'ignore))
        (rust-mode)))
    (setq-local lsp-mode t)
    (cl-letf (((symbol-function 'lsp-feature?) (lambda (_) t))
              ((symbol-function 'lsp-format-buffer)
               (lambda () (error "rustfmt parse failure"))))
      (should (equal (cdr (should-error (hypermodern/format-buffer)))
                     '("rustfmt parse failure")))
      (insert "incomplete Rust")
      (run-hooks 'before-save-hook)
      (should (equal (buffer-string) "incomplete Rust")))))

(ert-deftest hypermodern/other-languages-still-format ()
  "Keep the actual format-all pipeline for non-Rust buffers."
  (with-temp-buffer
    (emacs-lisp-mode)
    (should format-all-mode)
    (insert "(let ((x 1))\n(+ x 2))\n")
    (hypermodern/format-buffer)
    (should (equal (buffer-string) "(let ((x 1))\n  (+ x 2))\n"))))

(ert-deftest hypermodern/formatter-errors-visible ()
  (should (eq format-all-show-errors 'errors))
  ;; A direct format-all invocation must not retain the broken Rust-2015 path.
  (should-not (assoc "Rust" (default-value 'format-all-formatters))))

;;; emacs-format-tests.el ends here
