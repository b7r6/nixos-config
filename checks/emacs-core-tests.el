;;; emacs-core-tests.el --- Editor lifecycle regressions -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'comint)
(require 'compile)
(require 'dired)

(defconst hypermodern-core-test/config
  (file-name-as-directory (getenv "EMACS_TEST_CONFIG_DIR")))

(defun hypermodern-core-test/read (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun hypermodern-core-test/wait (predicate process)
  (let ((deadline (+ (float-time) 20)))
    (while (and (not (funcall predicate)) (process-live-p process)
                (< (float-time) deadline))
      (accept-process-output process .05))
    (unless (funcall predicate)
      (ert-fail (with-current-buffer (process-buffer process) (buffer-string))))))

(defun hypermodern-core-test/child (state body)
  "Start a fresh Emacs in STATE, without a bootstrap checkout or login env."
  (make-directory state t)
  (let ((process-environment (copy-sequence process-environment)))
    (setenv "NIX_PROFILES" nil)
    (setenv "EMACSDIR" nil)
    (make-process
     :name "emacs-core-child" :buffer (generate-new-buffer " *emacs-core-child*")
     :command
     (list (executable-find "emacs") "--batch"
           "--eval" (prin1-to-string
                     `(progn
                        (setq user-emacs-directory ,(file-name-as-directory state))
                        (require 'package) (package-initialize)
                        (advice-add 'url-retrieve-synchronously :override
                                    (lambda (&rest _) (error "Unexpected startup download")))))
           "-l" (concat hypermodern-core-test/config "early-init.el")
           "-l" (concat hypermodern-core-test/config "init.el")
           "--eval" (prin1-to-string body))
     :connection-type 'pipe :noquery t)))

(defun hypermodern-core-test/stop (process)
  (when (process-live-p process) (signal-process process 9))
  (while (process-live-p process) (accept-process-output process .05))
  (kill-buffer (process-buffer process)))

(ert-deftest hypermodern/core-fresh-offline-startup ()
  "Real packaged startup needs no stub, network, or NIX_PROFILES."
  (let* ((root (make-temp-file "emacs-startup-" t))
         (receipt (expand-file-name "receipt" root))
         (process
          (hypermodern-core-test/child
           root
           `(progn
              (unless (and hypermodern/nix-emacs-p (not (featurep 'straight))
                           ghostel-compile-global-mode file-name-handler-alist
                           (< gc-cons-threshold (* 1024 1024 1024)))
                (error "Startup invariant failed"))
              (with-temp-file ,receipt (insert "ready"))))))
    (unwind-protect
        (progn
          (hypermodern-core-test/wait (lambda () (file-exists-p receipt)) process)
          (should-not (file-exists-p (expand-file-name "straight" root))))
      (hypermodern-core-test/stop process)
      (delete-directory root t))))

(ert-deftest hypermodern/core-crash-recovery-and-session-isolation ()
  "Two live editors preserve distinct drafts; recover-session selects the right one."
  (let* ((root (make-temp-file "emacs-recovery-" t))
         (state (expand-file-name "state" root))
         (file (expand-file-name "draft.txt" root))
         (auto-save-list-file-prefix (expand-file-name "auto-save-list/.saves-" state))
         (original "on disk\n") processes receipts buffer)
    (with-temp-file file (insert original))
    (unwind-protect
        (progn
          (dotimes (i 2)
            (let* ((receipt (expand-file-name (format "receipt-%s" i) root))
                   (draft (format "unsaved draft %s\n" i))
                   (process
                    (hypermodern-core-test/child
                     state
                     `(progn
                        (find-file ,file)
                        ;; Interactive find-file enables this automatically;
                        ;; batch Emacs deliberately skips that startup step.
                        (auto-save-mode 1)
                        ;; The second editor must detect the first editor's
                        ;; lock. Simulate choosing to edit without stealing it.
                        (when (= ,i 1)
                          (unless (stringp (file-locked-p ,file))
                            (error "Other session's lock was not detected"))
                          (setq-local create-lockfiles nil))
                        (erase-buffer) (insert ,draft)
                        ;; Batch Emacs does not initialize the interactive
                        ;; startup ledger; use its ordinary PID/host naming.
                        (setq auto-save-list-file-name
                              (concat auto-save-list-file-prefix
                                      (number-to-string (emacs-pid)) "-test"))
                        (make-directory (file-name-directory auto-save-list-file-name) t)
                        (do-auto-save t)
                        (let ((copy buffer-auto-save-file-name))
                          (with-temp-file ,receipt
                            (prin1 (list copy auto-save-list-file-name) (current-buffer))))
                        (while t (accept-process-output nil .1))))))
              (push process processes)
              (hypermodern-core-test/wait (lambda () (file-exists-p receipt)) process)
              (push (read (hypermodern-core-test/read receipt)) receipts)))
          (should-not (equal (caar receipts) (caadr receipts)))
          (should (equal (hypermodern-core-test/read file) original))
          (dolist (process processes) (hypermodern-core-test/stop process))
          (setq processes nil)
          (cl-loop for (copy ledger) in receipts
                   for draft in '("unsaved draft 1\n" "unsaved draft 0\n") do
                   (should (equal (hypermodern-core-test/read copy) draft))
                   ;; Use the real session recovery command and its ledger.
                   ;; Only user prompts and the selected Dired row are supplied.
                   (cl-letf (((symbol-function 'dired-get-filename) (lambda (&rest _) ledger))
                             ((symbol-function 'dired-unmark) #'ignore)
                             ((symbol-function 'dired-do-flagged-delete) #'ignore)
                             ((symbol-function 'map-y-or-n-p)
                              (lambda (_prompt action files &rest _) (mapc action files)))
                             ((symbol-function 'read-answer) (lambda (&rest _) "yes")))
                     (let ((noninteractive nil))
                       (save-window-excursion (recover-session-finish))))
                   (setq buffer (get-file-buffer file))
                   (should (buffer-live-p buffer))
                   (with-current-buffer buffer
                     (should (equal (buffer-string) draft))
                     (should (buffer-modified-p))
                     (should (stringp buffer-auto-save-file-name))
                     (should-not (equal buffer-auto-save-file-name copy))
                     ;; Continuing to edit must save into the current session,
                     ;; while the selected crash copy remains recoverable.
                     (goto-char (point-max)) (insert "continued\n")
                     (do-auto-save t)
                     (should (equal (hypermodern-core-test/read buffer-auto-save-file-name)
                                    (concat draft "continued\n")))
                     (should (equal (hypermodern-core-test/read copy) draft))
                     (set-buffer-modified-p nil))
                   (kill-buffer buffer)
                   (should (equal (hypermodern-core-test/read file) original))))
      (mapc #'hypermodern-core-test/stop processes)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer (set-buffer-modified-p nil)) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest hypermodern/core-versioned-backups-cover-git ()
  "Saving a tracked file preserves the old on-disk content outside the repo."
  (let* ((root (file-name-as-directory (make-temp-file "emacs-backups-" t)))
         (default-directory root)
         (file (concat root "tracked.txt"))
         ;; Stock Emacs excludes /tmp from backups; these are test fixtures.
         (backup-enable-predicate (lambda (_) t)) buffer backups)
    (unwind-protect
        (progn
          (should (zerop (call-process "git" nil nil nil "init" "-q")))
          (with-temp-file file (insert "original\n"))
          (should (zerop (call-process "git" nil nil nil "add" "tracked.txt")))
          (setq buffer (find-file-noselect file))
          (with-current-buffer buffer
            (should (eq (vc-backend file) 'Git))
            (erase-buffer) (insert "replacement\n") (save-buffer))
          ;; Numbered backups replace the final ~ of the unnumbered name.
          (setq backups (file-expand-wildcards
                         (concat (string-remove-suffix "~" (make-backup-file-name file)) ".~*~")))
          (should (= (length backups) 1))
          (should-not (file-in-directory-p (car backups) root))
          (should (equal (hypermodern-core-test/read (car backups)) "original\n"))
          (should (equal (hypermodern-core-test/read file) "replacement\n")))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (mapc #'delete-file backups)
      (delete-directory root t))))

(ert-deftest hypermodern/core-comint-output ()
  "Real subprocess output survives Comint filtering with ANSI colors intact."
  (let ((buffer (generate-new-buffer " *comint-regression*")) process)
    (unwind-protect
        (with-current-buffer buffer
          (let ((process-connection-type nil))
            (make-comint-in-buffer "comint-regression" buffer (executable-find "cat")))
          (setq process (get-buffer-process buffer))
          (process-send-string process "plain\n\e[31mred\e[0m\n")
          (hypermodern-core-test/wait
           (lambda () (save-excursion (goto-char (point-min)) (search-forward "red" nil t))) process)
          (should (string-match-p "plain\nred\n" (buffer-string)))
          (goto-char (point-min)) (search-forward "red")
          (should (get-char-property (1- (point)) 'face))
          (should-not (string-match-p "\e\\[" (buffer-string))))
      (when (process-live-p process) (delete-process process))
      (kill-buffer buffer))))

(ert-deftest hypermodern/core-terminal-compile ()
  "M-x compile uses the actual native terminal and retains output on exit."
  (let* ((root (file-name-as-directory (make-temp-file "emacs-compile-" t)))
         (default-directory root)
         (compilation-ask-about-save nil)
         (compilation-save-buffers-predicate (lambda () nil))
         (shell-file-name (executable-find "sh")) buffer process)
    (unwind-protect
        (save-window-excursion
          (should ghostel-compile-global-mode)
          (setq buffer (compilation-start "printf '\033[32mterminal-ok\033[0m\\n'; exit 7"
                                          nil (lambda (_) "*core-compile*")))
          (with-current-buffer buffer
            (setq process ghostel--process)
            (should (derived-mode-p 'ghostel-mode))
            (hypermodern-core-test/wait (lambda () ghostel-compile--finalized) process)
            (should (derived-mode-p 'compilation-mode))
            (should (= ghostel-compile--last-exit 7))
            (should (string-match-p "terminal-ok" (buffer-string)))
            (should-not ghostel--redraw-timer)
            (should-not (memq process compilation-in-progress))))
      (when (process-live-p process) (delete-process process))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest hypermodern/core-eshell-activation ()
  "First Eshell load enables visual commands without a missed startup hook."
  (require 'eshell)
  (should (bound-and-true-p ghostel-eshell-visual-command-mode)))

(ert-deftest hypermodern/core-modeline-retention ()
  "Changing cursor positions keeps a bounded cache and still reuses hot tags."
  (load (concat hypermodern-core-test/config "hypermodern-palette.el") nil t)
  (load (concat hypermodern-core-test/config "hypermodern-modeline.el") nil t)
  (let ((hypermodern/modeline--cache (make-hash-table :test 'equal)))
    ;; The headless sandbox can construct SVGs; only the frame capability
    ;; guard is simulated. Exercise the production renderer and real GC.
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) t)))
      (dotimes (n (* 4 hypermodern/modeline-cache-limit))
        (hypermodern/modeline--tag (format "%s:0" n) 'plain)
        (should (<= (hash-table-count hypermodern/modeline--cache)
                    hypermodern/modeline-cache-limit)))
      (garbage-collect)
      (let ((tag (hypermodern/modeline--tag "hot" 'plain)))
        (should (eq tag (hypermodern/modeline--tag "hot" 'plain)))
        (should (get-text-property 0 'display tag)))
      (hypermodern/modeline-refresh)
      (should (zerop (hash-table-count hypermodern/modeline--cache))))))

(provide 'emacs-core-tests)
