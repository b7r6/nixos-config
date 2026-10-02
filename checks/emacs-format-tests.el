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
                  ((symbol-function 'hypermodern/rust-ready-p) (lambda () t))
                  ((symbol-function 'lsp--make-document-formatting-params) #'ignore)
                  ((symbol-function 'lsp-request)
                   (lambda (&rest _) (cl-incf calls) []))
                  ((symbol-function 'format-all-buffer)
                   (lambda (&rest _) (ert-fail "Rust reached format-all"))))
          (funcall mode)
          (setq-local lsp-mode t)
          (should-not format-all-mode)
          (should-not (memq 'rust-ts-flymake flymake-diagnostic-functions))
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
              ((symbol-function 'hypermodern/rust-ready-p) (lambda () t))
              ((symbol-function 'lsp--make-document-formatting-params) #'ignore)
              ((symbol-function 'lsp-request)
               (lambda (&rest _) (error "rustfmt parse failure"))))
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

(ert-deftest hypermodern/rust-format-startup-is-not-success ()
  "An advertised formatter is not proof that Cargo metadata has loaded."
  (with-temp-buffer
    (setq-local lsp-mode t)
    (cl-letf (((symbol-function 'lsp-feature?) (lambda (_) t))
              ((symbol-function 'hypermodern/rust-ready-p) (lambda () nil))
              ((symbol-function 'lsp-request)
               (lambda (&rest _) (ert-fail "Sent formatting before readiness"))))
      (should (string-match-p "still loading"
                              (error-message-string
                               (should-error (hypermodern/rust-format-buffer)
                                             :type 'user-error)))))))

(ert-deftest hypermodern/rust-format-rejects-stale-edits ()
  "A process filter or timer can change text during a synchronous LSP wait."
  (with-temp-buffer
    (insert "fn example() {}\n")
    (setq-local lsp-mode t)
    (cl-letf (((symbol-function 'lsp-feature?) (lambda (_) t))
              ((symbol-function 'hypermodern/rust-ready-p) (lambda () t))
              ((symbol-function 'lsp--make-document-formatting-params) #'ignore)
              ((symbol-function 'lsp-request)
               (lambda (&rest _) (insert "// intervening edit\n") [stale-edit]))
              ((symbol-function 'lsp--apply-text-edits)
               (lambda (&rest _) (ert-fail "Applied stale edits"))))
      (should-error (hypermodern/rust-format-buffer) :type 'user-error)
      (should (equal (buffer-string) "fn example() {}\n// intervening edit\n")))))

(ert-deftest hypermodern/rust-format-widens-and-restores-restriction ()
  "LSP ranges are relative to the full document, including in narrowed buffers."
  (with-temp-buffer
    (insert "fn first() {}\nfn second() {}\n")
    (narrow-to-region 15 (point-max))
    (let ((start (point-min)))
      (setq-local lsp-mode t)
      (cl-letf (((symbol-function 'lsp-feature?) (lambda (_) t))
                ((symbol-function 'hypermodern/rust-ready-p) (lambda () t))
                ((symbol-function 'lsp--make-document-formatting-params) #'ignore)
                ((symbol-function 'lsp-request)
                 (lambda (&rest _) (should (= (point-min) 1)) [edit]))
                ((symbol-function 'lsp--apply-text-edits)
                 (lambda (&rest _) (should (= (point-min) 1)))))
        (hypermodern/rust-format-buffer)
        (should (= (point-min) start))))))

(ert-deftest hypermodern/rust-readiness-is-per-server ()
  "A ready workspace cannot make a second workspace or restarted server ready."
  (let* ((hypermodern/rust-server-status (make-hash-table :test 'eq))
         (client (make-lsp-client :server-id 'rust-analyzer))
         (ready (make-lsp--workspace :client client :status 'initialized))
         (loading (make-lsp--workspace :client client :status 'initialized))
         (status (lsp-make-server-info :name "test")))
    (lsp-put status :health "ok")
    (lsp-put status :quiescent t)
    (hypermodern/rust-server-status-update ready status)
    (cl-letf (((symbol-function 'lsp-workspaces) (lambda () (list ready))))
      (should (hypermodern/rust-ready-p)))
    (cl-letf (((symbol-function 'lsp-workspaces) (lambda () (list loading))))
      (should-not (hypermodern/rust-ready-p)))
    (setf (lsp--workspace-status ready) 'shutdown)
    (cl-letf (((symbol-function 'lsp-workspaces) (lambda () (list ready))))
      (should-not (hypermodern/rust-ready-p)))))

(ert-deftest hypermodern/rust-format-null-is-not-already-formatted ()
  "A null result must not be described as proof of correct formatting."
  (with-temp-buffer
    (setq-local lsp-mode t)
    (let (reported)
      (cl-letf (((symbol-function 'lsp-feature?) (lambda (_) t))
                ((symbol-function 'hypermodern/rust-ready-p) (lambda () t))
                ((symbol-function 'lsp--make-document-formatting-params) #'ignore)
                ((symbol-function 'lsp-request) (lambda (&rest _) nil))
                ((symbol-function 'message)
                 (lambda (fmt &rest args) (setq reported (apply #'format fmt args)))))
        (hypermodern/rust-format-buffer)
        (should (equal reported "Rust formatter returned no edits"))))))

;;; emacs-format-tests.el ends here
