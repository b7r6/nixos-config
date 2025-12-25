;;; init.el --- -*- lexical-binding: t -*-
;;
;; "On The Design Of Text Editors" - https://arxiv.org/abs/2008.06030
;;
;; "There is always a point at which the terrorist ceases to manipulate the media
;;  gestalt. A point at which the violence may well escalate, but beyond which the
;;  terrorist has become symptomatic of the media gestalt itself. Terrorism as we
;;  ordinarily understand it is inately media-related. The Panther Moderns differ from
;;  other terrorists precisely in their degree of self-consciousness, in their
;;  awareness of the extent to which media divorce the act of terrorism from the
;;  original sociopolitical intent."
;;
;; "Skip it." Case said.

;; ============================================================
;; // memory // performance // optimization
;; ============================================================

(defvar hypermodern/gc-cons-threshold (* 256 1024 1024))

(setq
 gc-cons-threshold hypermodern/gc-cons-threshold
 gc-cons-percentage 0.1)

(add-hook
 'minibuffer-setup-hook
 (lambda ()
   (setq gc-cons-threshold most-positive-fixnum)))

(add-hook
 'minibuffer-exit-hook
 (lambda ()
   (garbage-collect)
   (setq gc-cons-threshold hypermodern/gc-cons-threshold)))

(setq copy-region-blink-delay 0)

;; ============================================================
;; // package // management
;; ============================================================

(require 'package)

;; add all mainstream archives...
(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa" . "https://melpa.org/packages/")
        ("melpa-stable" . "https://stable.melpa.org/packages/")))

;; prefer `MELPA` over `MELPA` stable
(setq package-archive-priorities
      '(("melpa" . 99)
        ("nongnu" . 80)
        ("gnu" . 70)
        ("melpa-stable" . 60)))

(package-initialize)

;; bootstrap use-package
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

(when (boundp 'hypermodern/install-extras)
  (use-package quelpa
    :ensure t
    :config
    (setq quelpa-update-melpa-p nil))

  (use-package quelpa-use-package
    :ensure t
    :after quelpa)

  (use-package auto-package-update
    :ensure t
    :config
    (setq auto-package-update-delete-old-versions t)
    (setq auto-package-update-hide-results t)))

(require 'package)

;; ============================================================
;; // forward // declarations
;; ============================================================

(declare-function eglot-format-buffer "eglot" ())
(declare-function eglot-rename "eglot" ())
(declare-function vertico-reverse-mode "vertico" ())
(declare-function hypermodern/format-haskell "init" ())
(declare-function disable-lsp-formatters "init" ())

;; TODO[b7r6]: we really want to handle these, but they break stuff...
(setq native-comp-async-report-warnings-errors nil)
(setq comp-async-report-warnings-errors nil)  ; Older variable name

;; ============================================================
;; // reinit // user // interface
;; ============================================================

(setq inhibit-startup-screen t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(setq frame-title-format "// %b //")
(set-face-attribute 'default nil :height 150)
(setq font-lock-maximum-decoration nil)
(setq auto-save-default nil)
(setq confirm-kill-processes nil)
(setq debug-on-error nil)
(setq echo-keystrokes 0.1)
(setq indent-tabs-mode nil)
(setq inhibit-startup-message t)
(setq initial-scratch-message "")
(setq make-backup-files nil)
(setq pop-up-windows nil)
(setq require-final-newline t)
(setq resize-mini-windows nil)
(setq ring-bell-function 'ignore)
(setq scroll-conservatively 10000)
(setq scroll-step 1)
(setq select-enable-clipboard t)
(setq split-height-threshold nil)
(setq split-width-threshold nil)
(setq transient-mark-mode t)
(setq cursor-in-non-selected-windows nil)
(setq backup-by-copying t)

(blink-cursor-mode +1)
(column-number-mode +1)
(display-time-mode +1)
(global-auto-revert-mode +1)
(global-hl-line-mode +1)
(show-paren-mode +1)
(fset 'yes-or-no-p 'y-or-n-p)

(setq-default indent-tabs-mode nil)
(setq make-backup-files nil)
(setq auto-save-default nil)
(setq create-lockfiles nil)

(use-package all-the-icons
  :ensure t)

(use-package nerd-icons
  :ensure t)

(when (boundp 'standard-display-table)
  (unless standard-display-table
    (setq standard-display-table (make-display-table)))
  (set-display-table-slot standard-display-table 'vertical-border ?│))

(setq-default visible-bell nil)
(setq-default ring-bell-function #'ignore)

;; ============================================================
;; // frame // discipline
;; ============================================================

(setq shackle-rules
      '((help-mode :other t :select t)               ; Reuse other window
        ("\\*Help\\*" :other t :select t)
        ("\\*info\\*" :other t :select t)
        ("\\*eldoc\\*" :other t :select nil)
        ("\\*eshell\\*" :same t :select t)           ; Reuse current window
        ("\\*shell\\*" :same t :select t)
        (vterm-mode :other t :select t)
        ("\\*Python\\*" :other t :select t)
        (compilation-mode :other t :select nil)
        ("\\*compilation\\*" :other t :select nil)
        ;; Keep some with align for specific placement needs
        ("\\*Warnings\\*" :align below :size 0.15 :select nil)
        ("\\*Backtrace\\*" :align below :size 0.25 :select t)))

(use-package popper
  :ensure t
  :after shackle
  :bind (("C-\\"   . popper-toggle)
         ("M-\\"   . popper-cycle)
         ("C-M-\\" . popper-toggle-type))
  :init
  (setq popper-reference-buffers
        '("\\*Messages\\*"
          "\\*Compile-Log\\*"
          "\\*compilation\\*"
          "\\*Backtrace\\*"
          "\\*Async Shell Command\\*"
          "\\*eshell\\*"
          "\\*shell\\*"
          "\\*rg\\*"
          "\\*grep\\*"
          "Output\\*$"
          help-mode
          compilation-mode
          inferior-python-mode))

  ;; Let Shackle handle placement
  (setq popper-display-control nil)

  :config
  (popper-mode +1)
  (popper-echo-mode +1))

;; ============================================================
;; // hypermodern // interactive
;; ============================================================

(defun hypermodern/reinit-vertical-divider (&optional sync-with-mode-line)
  "Set up clean modern window dividers for both GUI and terminal Emacs.
When SYNC-WITH-MODE-LINE is non-nil, attempt to match the divider color
with the mode-line background color."
  (interactive "P")
  ;; Remove custom face settings to inherit from theme
  (custom-set-faces
   '(vertical-border nil))

  ;; Clean up fringe indicators
  (setq-default fringe-indicator-alist '())
  (fringe-mode '(0 . 0))

  ;; Remove potential interference from mode-line positioning
  (setq-default
   mode-line-format
   (remove 'mode-line-position mode-line-format))

  ;; Set up unicode divider character for terminal Emacs
  (when (boundp 'standard-display-table)
    (unless standard-display-table
      (setq standard-display-table (make-display-table)))

    (set-display-table-slot
     standard-display-table 'vertical-border
     (make-glyph-code ?│))))

(hypermodern/reinit-vertical-divider)

(use-package base16-theme
  :ensure t)

;; ============================================================
;; // mode // line
;; ============================================================

(use-package doom-modeline
  :ensure t

  :init
  (doom-modeline-mode 1)

  :config
  (when (fboundp 'nerd-icons)
    (setq doom-modeline-icon t)
    (setq doom-modeline-major-mode-icon t)))

;; ============================================================
;; // hyper // modern // ai
;; ============================================================

(use-package gptel
  :ensure t
  :config

  (setq gptel-model 'anthropic/claude-opus-4
        gptel-backend
        (gptel-make-openai "// open // router"
          :host "openrouter.ai"
          :endpoint "/api/v1/chat/completions"
          :stream t
          :key "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"
          :models
          '(;; the old guard…
            anthropic/claude-opus-4            ;; world’s best
            anthropic/claude-sonnet-4          ;; fast & solid
            moonshotai/kimi-k2                 ;; long-form beast
            ;; …and the new kid
            qwen/qwen3-coder)))                ;; 262 K context MoE

  (defun hypermodern/gptel-configure-output ()
    "Configure output length based on model, always leaving room for input."
    (pcase gptel-model
      ('anthropic/claude-opus-4
       (setq gptel-response-length 8192 gptel-max-tokens 150000))
      ('anthropic/claude-sonnet-4
       (setq gptel-response-length 16384 gptel-max-tokens 130000))
      ('moonshotai/kimi-k2
       (setq gptel-response-length 32768 gptel-max-tokens 90000))
      ('qwen/qwen3-coder                 ; <-- new! 262 K context buffer
       (setq gptel-response-length 68000 ; plenty of room for input+output
             gptel-max-tokens (- 262144 (* 2 gptel-response-length))))
      (_
       (setq gptel-response-length 4096
             gptel-max-tokens 100000))))

  (defun hypermodern/gptel-switch-model ()
    "Switch between the four coding models."
    (interactive)
    (let* ((models '(("Opus 4 (Best)"       . anthropic/claude-opus-4.1)
                     ("Sonnet 4 (Fast)"     . anthropic/claude-sonnet-4)
                     ("Kimi K2 (Long)"      . moonshotai/kimi-k2)
                     ("Qwen Coder (Ultra)"  . qwen/qwen3-coder)))
           (choice (completing-read "Model: " (mapcar #'car models))))
      (setq gptel-model (cdr (assoc choice models)))
      (hypermodern/gptel-configure-output)
      (message "Switched to %s (max output: %d tokens)"
               choice gptel-response-length)))

  (defun hypermodern/gptel-check-tokens ()
    "Check estimated token usage before sending."
    (interactive)
    (let* ((content (if (use-region-p)
                        (buffer-substring-no-properties (region-beginning) (region-end))
                      (buffer-string)))
           (estimated-tokens (/ (length content) 4)) ; crude heuristic
           (total (+ estimated-tokens gptel-response-length)))
      (message "Estimated: %d input + %d output = %d total (query limit: %dK)"
               estimated-tokens gptel-response-length total
               (round (/ gptel-max-tokens 1000.0)))))

  (setq gptel--system-message nil)

  :bind (("C-c g g" . gptel)
         ("C-c g m" . gptel-menu)
         ("C-c g a" . hypermodern/gptel-switch-model)
         ("C-c g s" . gptel-send)
         ("C-c g r" . gptel-rewrite)
         ("C-c g t" . hypermodern/gptel-check-tokens)
         ("C-c g k" . gptel-abort))) ;; Abort request

;; ============================================================
;; completion // minibuffer // read
;; ============================================================

(use-package consult
  :ensure t)

(use-package all-the-icons-completion
  :ensure t
  :after all-the-icons
  :hook (marginalia-mode . all-the-icons-completion-marginalia-setup)
  :init
  (all-the-icons-completion-mode))

(use-package fzf
  :ensure t)

(use-package vertico
  :ensure t

  :config
  (vertico-mode)
  (vertico-reverse-mode))

(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless))
  (completion-category-defaults nil)
  (completion-category-overrides '((command (styles orderless))))
  )

;; (use-package posframe
;;   :ensure t)

(use-package marginalia
  :ensure t
  :init
  (marginalia-mode)
  :bind (:map minibuffer-local-map ("M-A" . marginalia-cycle)))

;; ============================================================
;; directories // projects // ripgrep
;; ============================================================

(use-package rg
  :ensure t
  :config
  (setq rg-default-directory (expand-file-name "."))

  (setq projectile-use-rg t)
  (setq rg-group-result t)
  (setq rg-context-line-count 2)
  (setq rg-show-columns t)
  (setq rg-command-line-flags '("--type=all"))

  (defun my-rg-project-prompt ()
    (interactive)
    (let ((current-prefix-arg '(4)))    ; Force prompt behavior
      (call-interactively 'rg-project)))

  ;; TODO[b7r6]: do this across modes, e.g. `vterm`...
  (with-eval-after-load 'rg
    (define-key rg-mode-map (kbd "M-N") nil)
    (define-key rg-mode-map (kbd "M-P") nil))

  :bind (("C-c C-r" . my-rg-project-prompt)
         ("C-c s p" . my-rg-project-prompt)
         ("C-c s d" . rg-dwim)
         ("C-c s l" . rg-list-searches)))

;; ============================================================
;; window // frame // movement
;; ============================================================

(defun hypermodern/scratch ()
  (let ((name "*scratch*"))
    (or (get-buffer name)
        (with-current-buffer (get-buffer-create name)
          (emacs-lisp-mode)
          (current-buffer)))))

(defun hypermodern/other ()
  (let ((buf (other-buffer (current-buffer) t)))
    (if (or (null buf) (eq buf (current-buffer)))
        (hypermodern/scratch)
      buf)))

(defun hypermodern/switch ()
  (let ((nw (next-window))
        (cb (current-buffer)))
    (with-selected-window nw
      (when (eq (window-buffer) cb)
        (switch-to-buffer (hypermodern/other))))))

(defun hypermodern/hsplit (&optional size)
  (interactive)
  (split-window-right size)
  (hypermodern/switch))

(defun hypermodern/vsplit (&optional size)
  (interactive)
  (split-window-below size)
  (hypermodern/switch))

(defun hypermodern/rotate-windows ()
  (interactive)
  (let* ((original-buffer (current-buffer))
         (windows (window-list))
         (buffers (mapcar #'window-buffer windows))
         (n (length windows)))
    (when (> n 1)
      (dotimes (i n)
        (set-window-buffer (nth i windows)
                           (nth (mod (1+ i) n) buffers)))
      (when-let ((w (get-buffer-window original-buffer t)))
        (select-window w)))))

;; ============================================================
;; // mode // hacking
;; ============================================================

(use-package paredit
  :hook ((emacs-lisp-mode lisp-mode scheme-mode) . paredit-mode))

(use-package paredit-everywhere
  :after paredit
  :hook (prog-mode . paredit-everywhere-mode))

(use-package direnv
  :config (direnv-mode 1))

;; ============================================================
;; magit // forge
;; ============================================================

(defun hypermodern/rightmost-window ()
  "Return the rightmost window in the current frame."
  (let ((best (selected-window)))
    (dolist (w (window-list))
      (when (> (window-left-column w) (window-left-column best))
        (setq best w)))
    best))

(defun hypermodern/magit-display-buffer (buffer)
  "Display Magit BUFFER in the rightmost window without splitting."
  (let ((win (if (one-window-p)
                 (selected-window)
               (hypermodern/rightmost-window))))
    (with-selected-window win
      (switch-to-buffer buffer))
    win))

(use-package magit
  :config
  (setq magit-display-buffer-function #'hypermodern/magit-display-buffer))

(use-package forge
  :if (locate-library "forge")
  :after magit)

;; ============================================================
;; // terminals (vterm + eat)
;; ============================================================

(use-package vterm
  :hook (vterm-mode . (lambda ()
                        (setq-local global-hl-line-mode nil)
                        ;; keep your movement keys alive
                        (setq vterm-keymap-exceptions '("M-/" "M-N" "M-P" "M-i" "M-z"))
                        (define-key vterm-mode-map (kbd "M-N") #'windmove-right)
                        (define-key vterm-mode-map (kbd "M-P") #'windmove-left))))

(use-package eat
  :if (locate-library "eat")
  :commands (eat))

(use-package clipetty
  :if (and (not (display-graphic-p)) (getenv "TMUX"))
  :hook (after-init . global-clipetty-mode))

;; ============================================================
;; dashboard
;; ============================================================

(defvar hypermodern/gibson-quotes
  '("he mythform is usually encountered in one of two modes..."
    "it was the style that mattered and the style was the same..."
    "all the speed he took, all the turns he'd taken..."
    "mirros, someone has once said..."
    "power, in case's world, meant corporate power..."
    "you're always building models..."
    "a gothic folly..."
    "senior is wealthy..."
    "and arranged to become a partron..."
    "he'd always imagined it as a gradual..."
    "well if feels like i am, kid..."))

(use-package dashboard
  :config
  (defvar hypermodern/dashboard-banner-file
    (expand-file-name "dashboard-banner-0x04.txt" user-emacs-directory))

  (defvar hypermodern/dashboard-banner-text
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                 // hypermodern
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

  (unless (file-exists-p hypermodern/dashboard-banner-file)
    (with-temp-file hypermodern/dashboard-banner-file
      (insert hypermodern/dashboard-banner-text)))

  (setq dashboard-startup-banner hypermodern/dashboard-banner-file
        dashboard-banner-logo-title
        (nth (random (length hypermodern/gibson-quotes)) hypermodern/gibson-quotes)
        dashboard-center-content t
        dashboard-set-heading-icons (display-graphic-p)
        dashboard-set-file-icons (display-graphic-p)
        dashboard-items '((recents . 5)))

  (dashboard-setup-startup-hook))

;; ============================================================
;; // general // key // bind
;; ============================================================

(use-package which-key
  :custom (which-key-idle-delay 1)
  :config (which-key-mode 1))

(use-package general
  :config
  (defun hypermodern/visit-init-file ()
    (interactive)
    (find-file user-init-file))

  (defun hypermodern/show-current-file ()
    (interactive)
    (message (or (buffer-file-name) "<no file>")))

  (defun hypermodern/kill-current-buffer ()
    (interactive)
    (kill-buffer (current-buffer)))

  (defvar hypermodern/default-font-height 150
    "Default font height for global font scaling.")

  (defun hypermodern/refresh-vertico ()
    "Refresh vertico display after font changes."
    (when (and (fboundp 'vertico-reverse-mode) vertico-reverse-mode)
      ;; Force a complete refresh of vertico
      (vertico-mode -1)
      (vertico-reverse-mode -1)
      (run-with-timer 0.1 nil 
        (lambda () 
          (vertico-mode 1)
          (vertico-reverse-mode 1)))))

  (defun hypermodern/global-font-size-increase ()
    "Increase font size globally across all buffers."
    (interactive)
    (let ((new-height (+ (face-attribute 'default :height) 10)))
      (set-face-attribute 'default nil :height new-height)
      (setq hypermodern/default-font-height new-height)
      (hypermodern/refresh-vertico)
      (message "Global font size: %d" new-height)))

  (defun hypermodern/global-font-size-decrease ()
    "Decrease font size globally across all buffers."
    (interactive)
    (let ((new-height (max 80 (- (face-attribute 'default :height) 10))))
      (set-face-attribute 'default nil :height new-height)
      (setq hypermodern/default-font-height new-height)
      (hypermodern/refresh-vertico)
      (message "Global font size: %d" new-height)))

  (defun hypermodern/global-font-size-reset ()
    "Reset font size to default globally."
    (interactive)
    (set-face-attribute 'default nil :height hypermodern/default-font-height)
    (hypermodern/refresh-vertico)
    (message "Global font size reset to: %d" hypermodern/default-font-height))

  (general-define-key
   ;; standard movement
   "C-c q"   #'join-line
   "C-c r"   #'revert-buffer
   "C-c d"   #'dashboard-open
   "C-j"     #'newline-and-indent

   ;; frame manipulation
   "C-x C-+" #'text-scale-increase
   "C-x C--" #'text-scale-decrease
   
   ;; standard font size controls (like browsers/terminals) - GLOBAL
   "C-+" #'hypermodern/global-font-size-increase
   "C--" #'hypermodern/global-font-size-decrease
   "C-0" #'hypermodern/global-font-size-reset

   ;; your standard keys
   "M-/"     #'undo
   "M-N"     #'windmove-right
   "M-P"     #'windmove-left
   "M-i"     #'hypermodern/visit-init-file
   "M-R"     #'hypermodern/rotate-windows

   ;; buffers
   "C-x 2"   #'hypermodern/vsplit
   "C-x 3"   #'hypermodern/hsplit
   "C-x k"   #'hypermodern/kill-current-buffer
   "C-c f"   #'hypermodern/show-current-file

   ;; git
   "C-x g"   #'magit))

;; A tiny “ops” prefix for the new candy.
(general-create-definer hypermodern/leader
  :prefix "C-c o")

;; We'll bind these after features load.

;; ============================================================
;; company or corfu (keep company for now, corfu optional)
;; ============================================================

(use-package company
  :hook (after-init . global-company-mode)
  :config
  (setq company-idle-delay 0.1
        company-minimum-prefix-length 1
        company-tooltip-idle-delay 0.05
        company-require-match nil
        company-show-quick-access t
        company-dabbrev-ignore-case t
        company-dabbrev-downcase nil
        company-backends '(company-capf
                           company-files
                           company-keywords
                           company-yasnippet
                           company-dabbrev-code
                           company-dabbrev))
  :bind (("M-TAB" . company-complete-common-or-cycle)
         ("C-M-i" . company-complete-common-or-cycle)))

(use-package yasnippet
  :config (yas-global-mode 1))

;; ============================================================
;; formatting (M-z) — one key, zero fighting
;; ============================================================

(use-package format-all
  :config
  (setq format-all-show-errors 'never)
  :hook (prog-mode . format-all-mode))

(defun hypermodern/biome-format-2-spaces ()
  "Format current buffer with biome, forcing 2-space indentation."
  (interactive)
  (unless (executable-find "biome")
    (user-error "biome not found on PATH"))
  (let* ((file (or (buffer-file-name) "file.js"))
         (content (buffer-substring-no-properties (point-min) (point-max)))
         (out (generate-new-buffer " *biome-format*"))
         (orig (current-buffer))
         (pt (point))
         (win-start (window-start)))
    (unwind-protect
        (with-current-buffer out
          (insert content)
          (if (zerop (call-process-region (point-min) (point-max)
                                          "biome" t t nil
                                          "format"
                                          "--stdin-file-path" file
                                          "--indent-width=2"
                                          "--indent-style=space"))
              (let ((formatted (buffer-string)))
                (with-current-buffer orig
                  (erase-buffer)
                  (insert formatted)
                  (goto-char (min pt (point-max)))
                  (set-window-start (selected-window) win-start t)
                  (message "[biome] formatted (2 spaces)")))
            (user-error "[biome] formatting failed")))
      (when (buffer-live-p out) (kill-buffer out)))))

(defun hypermodern/format-buffer ()
  "Format buffer: biome for JS/TS/JSON; else format-all."
  (interactive)
  (cond
   ((derived-mode-p 'js-mode 'js-ts-mode
                    'typescript-mode 'typescript-ts-mode
                    'tsx-ts-mode 'json-mode 'json-ts-mode)
    (hypermodern/biome-format-2-spaces))
   ((fboundp 'format-all-buffer)
    (format-all-buffer))
   (t
    (message "[format] no formatter available"))))

(global-set-key (kbd "M-z") #'hypermodern/format-buffer)

;; ============================================================
;; tree-sitter
;; ============================================================

(use-package treesit-auto
  :config
  (setq treesit-auto-install 'prompt)
  (global-treesit-auto-mode 1)
  
  ;; Auto-install common grammars
  (dolist (lang '(bash c cpp css html javascript json python typescript tsx yaml nix))
    (unless (treesit-language-available-p lang)
      (ignore-errors (treesit-install-language-grammar lang)))))

;; ============================================================
;; LSP (lsp-mode) — deduped, flymake-only diagnostics
;; ============================================================

;; lsp-mode internals have changed over time (list vs hash-table).
;; This helper keeps “register-if-missing” logic safe.
(defun hypermodern/lsp-client-registered-p (id)
  "Return non-nil if lsp-mode already has a client for server-id ID."
  (when (boundp 'lsp-clients)
    (cond
     ((hash-table-p lsp-clients) (gethash id lsp-clients))
     ((listp lsp-clients) (assoc id lsp-clients))
     (t nil))))

(use-package rainbow-mode
  :hook (prog-mode . rainbow-mode))

(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :init (setq lsp-keymap-prefix "C-c l")
  :config
  (setq lsp-idle-delay 0.5
        lsp-completion-provider :capf
        lsp-enable-symbol-highlighting t
        lsp-enable-snippet nil
        lsp-headerline-breadcrumb-enable t
        lsp-modeline-code-actions-enable t
        lsp-modeline-diagnostics-enable t
        lsp-log-io nil

        lsp-auto-guess-root t
        lsp-enable-file-watchers nil
        lsp-enable-suggest-server-download nil

        ;; flycheck-less life
        lsp-diagnostics-provider :flymake
        lsp-enable-on-type-formatting nil
        lsp-enable-indentation nil
        lsp-enable-formatting nil)

  ;; nixd: register if present (and not already registered)
  (when (executable-find "nixd")
    (unless (hypermodern/lsp-client-registered-p 'nixd)
      (lsp-register-client
       (make-lsp-client :new-connection (lsp-stdio-connection "nixd")
                        :major-modes '(nix-mode nix-ts-mode)
                        :priority 1
                        :server-id 'nixd)))))

(use-package lsp-ui
  :after lsp-mode
  :hook ((nix-mode nix-ts-mode) . lsp-ui-mode)
  :config
  (setq lsp-ui-sideline-enable t
        lsp-ui-sideline-show-code-actions nil
        lsp-ui-sideline-show-symbol nil
        lsp-ui-sideline-show-diagnostics nil
        lsp-ui-sideline-show-hover t
        lsp-ui-sideline-delay 1.0
        lsp-ui-sideline-update-mode 'point
        lsp-ui-doc-enable t
        lsp-ui-doc-show-with-cursor nil
        lsp-ui-doc-show-with-mouse nil
        lsp-inlay-hint-enable nil
        lsp-lens-enable nil))

;; Flymake: fringe-only, no wavy underlines.
(with-eval-after-load 'flymake
  (set-face-attribute 'flymake-error nil :underline nil)
  (set-face-attribute 'flymake-warning nil :underline nil)
  (set-face-attribute 'flymake-note nil :underline nil)

  (setq flymake-fringe-indicator-position 'left-fringe
        flymake-no-changes-timeout 0.5
        flymake-start-on-save-buffer t))

;; ============================================================
;; Python: choose basedpyright vs ruff-lsp deterministically
;; ============================================================

(use-package lsp-pyright
  :if (locate-library "lsp-pyright")
  :after lsp-mode
  :config
  (setq lsp-pyright-langserver-command "basedpyright-langserver")
  (setenv "NODE_OPTIONS" "--max-old-space-size=24576")
  (setq lsp-pyright-typechecking-mode "basic"
        lsp-pyright-diagnostic-mode "openFilesOnly"
        lsp-pyright-venv-strategy "useBestEffort"
        lsp-pyright-basedpyright-inlay-hints nil
        lsp-pyright-exclude
        ["**/node_modules" "**/__pycache__" "**/data" "**/datasets"
         "**/checkpoints" "**/wandb" "**/.venv" "**/venv" "**/*.ipynb"]))

;; Register Ruff LSP client (ruff server). Guard against double-register.
(with-eval-after-load 'lsp-mode
  (unless (hypermodern/lsp-client-registered-p 'ruff-lsp)
    (lsp-register-client
     (make-lsp-client
      :new-connection (lsp-stdio-connection '("ruff" "server" "--preview"))
      :activation-fn (lsp-activate-on "python")
      :server-id 'ruff-lsp
      :priority 1))))

(defvar hypermodern/python-lsp-backend 'basedpyright
  "Current Python LSP backend. Either 'basedpyright or 'ruff.")

(defun hypermodern/python-use-basedpyright ()
  (interactive)
  (setq hypermodern/python-lsp-backend 'basedpyright)
  (message "Python LSP → BasedPyright")
  (when (bound-and-true-p lsp-mode) (lsp-restart-workspace)))

(defun hypermodern/python-use-ruff ()
  (interactive)
  (setq hypermodern/python-lsp-backend 'ruff)
  (message "Python LSP → Ruff")
  (when (bound-and-true-p lsp-mode) (lsp-restart-workspace)))

(defun hypermodern/python-switch-lsp ()
  (interactive)
  (if (eq hypermodern/python-lsp-backend 'basedpyright)
      (hypermodern/python-use-ruff)
    (hypermodern/python-use-basedpyright)))

(defun hypermodern/python-lsp-init ()
  "Select Python client before LSP starts."
  (pcase hypermodern/python-lsp-backend
    ('ruff
     (setq-local lsp-enabled-clients '(ruff-lsp))
     (setq-local lsp-disabled-clients '(pyright)))
    (_
     (setq-local lsp-enabled-clients '(pyright))
     (setq-local lsp-disabled-clients '(ruff-lsp))))
  (when (< (buffer-size) (* 10 1024 1024))
    (lsp-deferred)))

(add-hook 'python-mode-hook #'hypermodern/python-lsp-init)
(add-hook 'python-ts-mode-hook #'hypermodern/python-lsp-init)

(global-set-key (kbd "C-c p l") #'hypermodern/python-switch-lsp)
(global-set-key (kbd "C-c p b") #'hypermodern/python-use-basedpyright)
(global-set-key (kbd "C-c p r") #'hypermodern/python-use-ruff)

;; ============================================================
;; language modes (keep your set, but fix hooks)
;; ============================================================

(use-package csharp-mode
  :mode "\\.cs\\'")

(use-package fsharp-mode
  :mode "\\.fs[ix]?\\'")

(use-package sh-script
  :ensure nil
  :mode (("\\.sh\\'" . bash-ts-mode)
         ("\\.bash\\'" . bash-ts-mode)))

(use-package haskell-mode
  :mode (("\\.hs\\'" . haskell-mode)
         ("\\.lhs\\'" . literate-haskell-mode)
         ("\\.cabal\\'" . haskell-cabal-mode)
         ("\\.hsc\\'" . haskell-mode))
  :config
  (setq haskell-tags-on-save nil
        haskell-stylish-on-save nil
        haskell-process-type nil))

(use-package lsp-haskell
  :if (locate-library "lsp-haskell")
  :after (haskell-mode lsp-mode)
  :config
  (setq lsp-haskell-server-path "haskell-language-server-wrapper"
        lsp-haskell-plugin-stan-global-on nil
        lsp-haskell-plugin-hlint-global-on t
        lsp-haskell-formatting-provider "fourmolu"))

(use-package nix-mode
  :mode "\\.nix\\'")

(use-package typescript-ts-mode
  :ensure nil
  :mode (("\\.ts\\'"  . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode)
         ("\\.js\\'"  . js-ts-mode)
         ("\\.jsx\\'" . js-ts-mode))
  :hook ((typescript-ts-mode . (lambda ()
                                 (setq-local tab-width 2
                                             indent-tabs-mode nil
                                             typescript-ts-mode-indent-offset 2)))
         (tsx-ts-mode . (lambda ()
                          (setq-local tab-width 2
                                      indent-tabs-mode nil
                                      typescript-ts-mode-indent-offset 2)))
         (js-ts-mode . (lambda ()
                         (setq-local tab-width 2
                                     indent-tabs-mode nil
                                     js-ts-mode-indent-offset 2)))))

(use-package typescript-mode
  :hook (typescript-mode . (lambda ()
                             (setq-local tab-width 2
                                         indent-tabs-mode nil
                                         typescript-indent-level 2))))

;; Generic LSP startup (avoid python; it has special init above).
(dolist (hook '(c-mode-hook c-ts-mode-hook
                            c++-mode-hook c++-ts-mode-hook
                            csharp-mode-hook csharp-ts-mode-hook
                            fsharp-mode-hook
                            haskell-mode-hook haskell-ts-mode-hook
                            js-ts-mode-hook tsx-ts-mode-hook typescript-ts-mode-hook
                            nix-mode-hook nix-ts-mode-hook
                            sh-mode-hook bash-ts-mode-hook))
  (add-hook hook #'lsp-deferred))

;; ============================================================
;; web (EWW + xwidget-webkit + atomic-chrome)
;; ============================================================

(use-package eww
  :ensure nil
  :commands (eww eww-browse-url))

(defun hypermodern/webkit (url)
  "Browse URL using xwidget-webkit if available."
  (interactive "sURL: ")
  (if (fboundp 'xwidget-webkit-browse-url)
      (xwidget-webkit-browse-url url)
    (user-error "No xwidget-webkit in this Emacs build")))

(use-package atomic-chrome
  :if (locate-library "atomic-chrome")
  :config
  (setq atomic-chrome-default-major-mode 'markdown-mode)
  (atomic-chrome-start-server))

;; ============================================================
;; comms (IRC / Matrix / Telegram / Fediverse)
;; ============================================================

(use-package erc
  :ensure nil
  :commands (erc erc-tls)
  :config
  (setq erc-server "irc.libera.chat"
        erc-nick (or (getenv "ERC_NICK") "b7r6")
        erc-user-full-name user-full-name
        erc-autojoin-channels-alist '(("irc.libera.chat" "#emacs" "#nixos"))
        erc-prompt-for-nickserv-password nil
        ;; Use auth-source for NickServ. Put it in authinfo/pass.
        ;; machine irc.libera.chat login <nick> password <nickserv-pass>
        erc-use-auth-source-for-nickserv-password t
        erc-modules '(autojoin button completion fill irccontrols list
                               match menu move-to-prompt netsplit
                               notifications readonly ring services
                               smiley spelling track)))

(defun hypermodern/irc ()
  (interactive)
  (erc-tls :server "irc.libera.chat" :port 6697 :nick erc-nick))

(use-package ement
  :if (locate-library "ement")
  :commands (ement-connect))

(use-package telega
  :if (locate-library "telega")
  :commands (telega))

(use-package mastodon
  :if (locate-library "mastodon")
  :commands (mastodon))

;; ============================================================
;; info (RSS) + docs (PDF/EPUB)
;; ============================================================

(use-package elfeed
  :if (locate-library "elfeed")
  :commands (elfeed)
  :config
  (setq elfeed-feeds
        '("https://planet.emacslife.com/atom.xml"
          "https://hnrss.org/frontpage"
          "https://nixos.org/blog/announcements-rss.xml")))

(use-package pdf-tools
  :if (locate-library "pdf-tools")
  :mode ("\\.pdf\\'" . pdf-view-mode)
  :config
  ;; On Nix this is usually already built; harmless if re-run.
  (condition-case err
      (pdf-tools-install)
    (error (message "[pdf-tools] install failed: %s" err))))

(use-package nov
  :if (locate-library "nov")
  :mode ("\\.epub\\'" . nov-mode))

;; ============================================================
;; R2 password-store backup (rclone) — manual trigger from Emacs
;; ============================================================

(defun hypermodern/r2-password-store-backup ()
  "Backup ~/.password-store to rclone remote `r2crypt:password-store`."
  (interactive)
  (compile "rclone sync ~/.password-store r2crypt:password-store --checksum --fast-list --create-empty-src-dirs"))

;; ============================================================
;; ops leader keys
;; ============================================================


(defun hypermodern/call-or-warn (fn label)
  "Call FN interactively if it exists, else complain with LABEL."
  (if (fboundp fn)
      (call-interactively fn)
    (user-error "[hypermodern] %s not available (missing package?)" label)))

(defun hypermodern/ement ()
  (interactive)
  (hypermodern/call-or-warn 'ement-connect "ement"))

(defun hypermodern/telega ()
  (interactive)
  (hypermodern/call-or-warn 'telega "telega"))

(defun hypermodern/elfeed ()
  (interactive)
  (hypermodern/call-or-warn 'elfeed "elfeed"))

(defun hypermodern/mastodon ()
  (interactive)
  (hypermodern/call-or-warn 'mastodon "mastodon"))

(hypermodern/leader
  "w"  #'eww
  "W"  #'hypermodern/webkit
  "i"  #'hypermodern/irc
  "m"  #'hypermodern/ement
  "t"  #'hypermodern/telega
  "M"  #'hypermodern/mastodon
  "f"  #'hypermodern/elfeed
  "p"  #'hypermodern/r2-password-store-backup)

;; ============================================================
;; // tramp // fixes
;; ============================================================

(use-package tramp
  :ensure nil
  :config
  ;; Use simpler method for local edits
  (setq tramp-default-method "ssh")
  
  ;; Disable ControlMaster which can cause issues
  (setq tramp-use-ssh-controlmaster-options nil)
  
  ;; Don't save history
  (setq tramp-histfile-override nil)
  
  ;; Simpler prompt detection
  (setq tramp-shell-prompt-pattern 
        "\\(?:^\\|\r\\)[^]#$%>\n]*#?[]#$%>].* *\\(^[\\[[0-9;]*[a-zA-Z] *\\)*")
  
  ;; Don't use VC on remote files (faster)
  (setq vc-ignore-dir-regexp
        (format "\\(%s\\)\\|\\(%s\\)"
                vc-ignore-dir-regexp
                tramp-file-name-regexp))
  
  ;; Backup settings
  (setq tramp-backup-directory-alist backup-directory-alist)
  
  ;; Auto-save settings  
  (setq tramp-auto-save-directory temporary-file-directory))

;; Clean connections before trying
(defun hypermodern/tramp-cleanup ()
  "Clean all TRAMP connections."
  (interactive)
  (tramp-cleanup-all-connections)
  (tramp-cleanup-all-buffers)
  (message "TRAMP connections cleaned"))

(global-set-key (kbd "C-c t c") #'hypermodern/tramp-cleanup)

(require 'hypermodern-ui nil 'noerror)
(when (featurep 'hypermodern-ui)
  ;; default: your minimal taste, with a subtle glow layer
  (setq hypermodern/ui-theme 'base16-ono-sendai-blue-tuned
        hypermodern/ui-density 'tight
        hypermodern/ui-signal 'minimal
        hypermodern/ui-font-preset 'auto

        ;; glow-up defaults (still disciplined)
        hypermodern/ui-glow-level 'subtle
        hypermodern/ui-glow-halo 'auto
        hypermodern/ui-enable-pulse t
        hypermodern/ui-cursor-style nil)

  ;; Try to ensure the theme is available before initializing
  (ignore-errors (require 'base16-ono-sendai-blue-tuned-theme))
  (hypermodern/ui-init)
  (global-set-key (kbd "C-c o u") #'hypermodern/ui-menu))

(provide 'init)
;;; init.el ends here
