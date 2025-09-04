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
;; memory // performance // optimization
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
;; package // management // human // agent // hybrid
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
;; ui // reinit
;; ============================================================

(setq inhibit-startup-screen t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(setq frame-title-format "// %b //")
(set-face-attribute 'default nil :height 100)
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

;; (defun hypermodern/remove-face-decorations ()
;;   "Remove all bold and italic attributes from all faces."
;;   (mapc (lambda (face)
;;           (when (face-attribute face :weight nil t)
;;             (set-face-attribute face nil :weight 'normal))
;;           (when (face-attribute face :slant nil t)
;;             (set-face-attribute face nil :slant 'normal)))
;;         (face-list)))
;; (add-hook 'after-init-hook
;;           (lambda ()
;;             (run-with-timer 0.1 nil 'hypermodern/remove-face-decorations)))
;; (advice-add 'load-theme :after
;;             (lambda (&rest _)
;;               (hypermodern/remove-face-decorations)))

;; ============================================================
;; hyper // modern // interactive
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

(use-package base16-theme
  :ensure t)

;; ============================================================
;; mode // line
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
;; hyper // modern // ai
;; ============================================================

(use-package gptel
  :ensure t
  :config

  ;; OpenRouter backend – the four coding champions
  (setq gptel-model 'anthropic/claude-opus-4.1         ;;  default start-up model
        gptel-backend
        (gptel-make-openai "// open // router"
          :host "openrouter.ai"
          :endpoint "/api/v1/chat/completions"
          :stream t
          :key (lambda ()
                 (or (getenv "OPENROUTER_API_KEY")
                     (auth-source-pick-first-password
                      :host "api.openrouter.ai")))
          :models
          '(;; the old guard…
            anthropic/claude-opus-4            ;; world’s best
            anthropic/claude-sonnet-4          ;; fast & solid
            moonshotai/kimi-k2                 ;; long-form beast
            ;; …and the new kid
            qwen/qwen3-coder)))                ;; 262 K context MoE

  ;; Model-specific settings ---------------------------------------------------
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

  ;; Quick model switcher now with Coder Qwen included -------------------------
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

  ;; Token estimator & prompt-less system message unchanged --------------------
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

  :init

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
  ;; Set default directory to search in
  (setq rg-default-directory (expand-file-name "."))

  ;; Use ripgrep as the default search tool in Projectile
  (setq projectile-use-rg t)

  ;; Group search results by file
  (setq rg-group-result t)

  ;; Context lines: 2 lines before and after the match
  (setq rg-context-line-count 2)

  ;; Show search results in a new window
  (setq rg-show-columns t)

  ;; Always search all files in project
  (setq rg-command-line-flags '("--type=all"))

  (defun my-rg-project-prompt ()
    (interactive)
    (let ((current-prefix-arg '(4)))    ; Force prompt behavior
      (call-interactively 'rg-project)))

  ;; Unbind M-N and M-P from rg-mode-map
  (with-eval-after-load 'rg
    (define-key rg-mode-map (kbd "M-N") nil)
    (define-key rg-mode-map (kbd "M-P") nil))

  ;; Keybindings
  :bind (("C-c C-r" . my-rg-project-prompt)
         ("C-c s p" . my-rg-project-prompt)
         ("C-c s d" . rg-dwim)
         ("C-c s l" . rg-list-searches)))

;; ============================================================
;; window // frame // movement
;; ============================================================

(defun hypermodern/scratch ()
  (let ((scratch-name "*scratch*"))
    (if (get-buffer scratch-name)
        (get-buffer scratch-name)
      (let ((buf (get-buffer-create scratch-name)))
        (with-current-buffer buf
          (emacs-lisp-mode))
        buf))))

;; (defun hypermodern/scratch ()
;;   (let ((dir (if buffer-file-name
;; 	         (file-name-directory buffer-file-name)
;;                default-directory)))
;;     (get-buffer-create (concat dir "elisp-scratch.el"))))

(defun hypermodern/other ()
  (let ((buf (other-buffer (current-buffer))))
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
         (buffers (mapcar 'window-buffer windows))
         (num-windows (length windows)))
    (when (> num-windows 1)
      (dotimes (i num-windows)
        (set-window-buffer
         (nth i windows) (nth (mod (+ i 1) num-windows) buffers)))
      (let ((original-window (get-buffer-window original-buffer t)))
        (when original-window
          (select-window original-window))))))

;; ============================================================
;; mode // hacking
;; ============================================================

(use-package paredit
  :ensure t
  :hook ((emacs-lisp-mode lisp-mode scheme-mode) . paredit-mode))

(use-package paredit-everywhere
  :ensure t
  :after paredit
  :hook (prog-mode . paredit-everywhere-mode))

(use-package direnv
  :ensure t
  :config
  (direnv-mode 1))

;; ============================================================
;; magit // init
;; ============================================================

(defun hypermodern/magit-display-buffer-function (buffer)
  "Display BUFFER in the rightmost window without splitting."
  (let ((window (if (one-window-p)
                    (selected-window)
                  (let ((windows (window-list)))
                    (car (last windows))))))
    (when window
      (select-window window)
      (set-window-buffer window buffer)
      window)))

;; (defun hypermodern/magit-display-buffer-function (buffer)
;;   "Display BUFFER in the rightmost window without splitting."
;;   (let ((window (if (one-window-p)
;;                     (selected-window)
;;                   (window-at (- (frame-width) 2) 1))))
;;     (select-window window)
;;     (set-window-buffer window buffer)
;;     window))

(use-package magit
  :ensure t
  :config
  (setq magit-display-buffer-function #'hypermodern/magit-display-buffer-function))

;; ============================================================
;; edit // compile // test
;; ============================================================

(use-package compile
  :ensure nil
  :config
  (add-hook 'compilation-filter-hook 'ansi-color-compilation-filter))

;; ============================================================
;; vterm
;; ============================================================

(defun setup-vterm ()
  (setq vterm-keymap-exceptions '("M-/" "M-N" "M-P" "M-i" "M-z"))
  (define-key vterm-mode-map (kbd "M-N") 'windmove-right)
  (define-key vterm-mode-map (kbd "M-P") 'windmove-left))

(use-package vterm
  :ensure t
  :config

  :hook
  (vterm-mode . (lambda ()
                  (setq-local global-hl-line-mode nil)
                  (setup-vterm))))

;; ============================================================
;; tmux // copy // paste
;; ============================================================
(use-package clipetty
  :ensure t
  :hook (after-init . global-clipetty-mode))

;; ============================================================
;; dashboard // mode
;; ============================================================

(defvar hypermodern/gibson-quotes
  '("he mythform is usually encountered in one of two modes. one mode
assumes that the cyberspace matric is inhabited, or perhaps visited, by
entities whose characteristics correspond with the primary mythoform
of a hidden people."

    "it was the style that mattered and the style was the same.
the moderns were mercenaries, practical jokers, nihilistic technofetishists."

    "all the speed he took, all the turns he'd taken and the corners he'd cut
in night city, and still he'd see the matrix in his sleep, bright lattices
of logic unfolding across that colorless void..."

    "mirros, someone has once said, where in some way essentially
unwholesome, constructs were more so, she decided."

    "power, in case's world, meant corporate power. the zaibatsus,
the multinationals that shaped the course of human history,
had transcended old barriers."

    "you're always building models. stone circles. cathedrals.
pipe-organs. adding machines. i got no idea why i'm here now."

    "a gothic folly. endless series of chambers linked by passages,
by stairwells vaulted like intestines."

    "senior is wealthy. senior enjoys any number of means of manifestation."

    "and arranged to become a partron of the aeschmann colection. the aeschmann
collection was restricted to the work of psychotics."

    "he'd always imagined it as a gradual and willing accommodation of
the machine, the parent organism. it was the root of street cool too, the
knowing posture that implied connection, invisible lines up to hidden
levels of influence."

    "well if feels like i am, kid, but i'm really just a bunch of
rom, it's one of them, ah, philosophical questions i guess. but i aint's likely
to write you no poem, if you follow me, your ai? it just might. bit it ain't
no way human."))

(use-package dashboard
  :ensure t
  :config

  (defvar my-custom-banner-file
    (expand-file-name "dashboard-banner-0x04.txt" user-emacs-directory))

  (defvar my-custom-banner-text
    "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                 // hypermodern
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

  (unless (file-exists-p my-custom-banner-file)
    (with-temp-file my-custom-banner-file
      (insert my-custom-banner-text)))

  (setq dashboard-startup-banner my-custom-banner-file)

  (setq dashboard-banner-logo-title
        (nth (random (length hypermodern/gibson-quotes))
             hypermodern/gibson-quotes))

  (setq dashboard-center-content t)
  (setq dashboard-set-heading-icons t)
  (setq dashboard-set-file-icons t)

  (setq dashboard-items '((recents . 5)))
  (dashboard-setup-startup-hook))

;; ============================================================
;; general // key // bind
;; ============================================================

(use-package which-key
  :ensure t
  :custom
  (which-key-idle-delay 1)

  :config
  (which-key-mode))

(use-package general
  :ensure t
  :config

  (defun hypermodern/what-face (pos)
    "Display the face at POS."
    (interactive "d")
    (let ((face (or (get-char-property (point) 'read-face-name)
                    (get-char-property (point) 'face))))
      (if face (message "Face: %s" face) (message "No face at %d" pos))))

  (defun hypermodern/show-current-file ()
    "Print the current buffer filename to the minibuffer."
    (interactive)
    (message (buffer-file-name)))

  (defun hypermodern/kill-current-buffer ()
    "Kill the current buffer."
    (interactive)
    (kill-buffer (current-buffer)))

  (defun hypermodern/visit-init-file ()
    (interactive)
    (find-file user-init-file))

  (defun hypermodern/format-all-buffer ()
    "Format buffer if formatter is available, otherwise message."
    (interactive)
    (condition-case err
        (format-all-buffer)
      (error (message "[emacs] formatter not available: %s" err))))

  (general-define-key
   ;; standard movement
   "C-c q"   'join-line
   "C-c r"   'revert-buffer
   "C-c d"   'dashboard-open
   "C-j"     'newline-and-indent

   ;; frame mainpulation
   "C-x C-+" 'text-scale-increase
   "C-x C--" 'text-scale-decrease
   "C-x C-r" 'rg-dwim-project-dir
   "C-x d"   'consult-recent-file
   "C-x f"   'consult-fd

   ;; `b7r6` standard keys
   "M-/"     'undo
   "M-N"     'windmove-right
   "M-P"     'windmove-left
   "M-i"     'hypermodern/visit-init-file
   "M-z"     'hypermodern/format-all-buffer

   ;; `hypermodern` overrides
   "C-M-r"   'consult-ripgrep
   "M-R"     'hypermodern/rotate-windows
   "C-c f"   'hypermodern/show-current-file
   "C-x 2"   'hypermodern/vsplit
   "C-x 3"   'hypermodern/hsplit
   "C-x k"   'hypermodern/kill-current-buffer))

;; ============================================================
;; company // complete
;; ============================================================

(use-package company
  :ensure t
  :hook (after-init . global-company-mode)

  :config
  (setq company-idle-delay 0.25)
  (setq company-minimum-prefix-length 1)
  (setq company-backends
        '(company-capf
          company-files
          company-keywords
          company-yasnippet
          company-dabbrev-code
          company-dabbrev))

  (setq company-dabbrev-ignore-case t)
  (setq company-dabbrev-downcase nil)
  (setq company-show-quick-access t)
  (setq company-tooltip-idle-delay 0.1)
  (setq company-require-match nil)

  :bind (("M-TAB" . company-complete-common-or-cycle)
         ("C-M-i" . company-complete-common-or-cycle)))

;; ============================================================
;;                   hacker // essential
;; ============================================================

;; ============================================================
;; formatting // configuration
;; ============================================================

;; ============================================================
;; formatting // configuration
;; ============================================================

(use-package format-all
  :ensure t

  :config
  (setq format-all-show-errors 'never)

  ;; Force Biome to use 2-space indentation
  (defun hypermodern/biome-args ()
    "Return Biome formatter arguments with 2-space indentation."
    '("format" "--stdin-file-path" filepath "--indent-width=2" "--indent-style=space"))

  (setq-default format-all-formatters
                '(("C++"          . (clang-format))
                  ("C#"           . (clang-format))
                  ("CSS"          . (prettier))
                  ("F#"           . (fantomas))
                  ("Go"           . (gofmt))
                  ("HTML"         . (prettier))
                  ("Haskell"      . (fourmolu))
                  ("JavaScript"   . (biome . hypermodern/biome-args))
                  ("JSON"         . (biome . hypermodern/biome-args))
                  ("Markdown"     . (mdformat))
                  ("Nix"          . (nixfmt))
                  ("Python"       . (ruff))
                  ("Ruby"         . (rubocop))
                  ("Rust"         . (rustfmt))
                  ("Shell"        . (shfmt "-i" "2"))  ; 2-space for shell too
                  ("TypeScript"   . (biome . hypermodern/biome-args))
                  ("TSX"          . (biome . hypermodern/biome-args))
                  ("YAML"         . (yamlfmt))
                  ("TOML"         . (taplo))
                  ("Terraform"    . (terraform))
                  ("HCL"          . (hclfmt))
                  ("Zig"          . (zig))

                  ;; TreeSit mode mappings
                  (c-ts-mode      . (clang-format))
                  (c++-ts-mode    . (clang-format))
                  (csharp-ts-mode . (clang-format))
                  (css-ts-mode    . (prettier))
                  (go-ts-mode     . (gofmt))
                  (html-ts-mode   . (prettier))
                  (js-ts-mode     . (biome . hypermodern/biome-args))
                  (json-ts-mode   . (biome . hypermodern/biome-args))
                  (python-ts-mode . (ruff))
                  (rust-ts-mode   . (rustfmt))
                  (bash-ts-mode   . (shfmt "-i" "2"))
                  (sh-mode        . (shfmt "-i" "2"))
                  (typescript-ts-mode . (biome . hypermodern/biome-args))
                  (tsx-ts-mode    . (biome . hypermodern/biome-args))
                  (yaml-ts-mode   . (yamlfmt))
                  (nix-mode       . (nixfmt))
                  (toml-ts-mode   . (taplo))
                  (zig-mode       . (zig))

                  ;; Traditional mode mappings
                  (c-mode         . (clang-format))
                  (c++-mode       . (clang-format))
                  (csharp-mode    . (clang-format))
                  (css-mode       . (prettier))
                  (go-mode        . (gofmt))
                  (html-mode      . (prettier))
                  (js-mode        . (biome . hypermodern/biome-args))
                  (js2-mode       . (biome . hypermodern/biome-args))
                  (json-mode      . (biome . hypermodern/biome-args))
                  (python-mode    . (ruff))
                  (ruby-mode      . (rubocop))
                  (rust-mode      . (rustfmt))
                  (typescript-mode . (biome . hypermodern/biome-args))
                  (nix-mode       . (nixfmt))
                  (yaml-mode      . (yamlfmt))
                  (markdown-mode  . (mdformat))
                  (terraform-mode . (terraform))
                  (hcl-mode       . (hclfmt))
                  (toml-mode      . (taplo))))

  ;; Custom function for Haskell's two-pass formatting
  (defun hypermodern/format-haskell ()
    "Run fourmolu then stylish-haskell for peak aesthetics."
    (when (derived-mode-p 'haskell-mode)
      (format-all-buffer)  ; fourmolu via format-all
      ;; (haskell-mode-stylish-buffer)   ; then stylish
      ))

  ;; Override format-all for Haskell
  (defun hypermodern/format-all-buffer-override ()
    "Format buffer with special handling for Haskell."
    (interactive)
    (if (derived-mode-p 'haskell-mode)
        (hypermodern/format-haskell)
      (format-all-buffer)))

  ;; Rebind M-z to our override
  (global-set-key (kbd "M-z") 'hypermodern/format-all-buffer-override)

  ;; Disable lsp formatters as before
  (defun disable-lsp-formatters ()
    (when (and (boundp 'eglot--managed-mode) eglot--managed-mode)
      (remove-hook 'before-save-hook #'eglot-format-buffer t))
    (when (and (boundp 'lsp-mode) lsp-mode)
      (setq-local lsp-enable-on-type-formatting nil)
      (setq-local lsp-enable-indentation nil)
      (setq-local lsp-enable-formatting nil)))

  (add-hook 'format-all-mode-hook #'disable-lsp-formatters)

  :bind ("M-z" . format-all-buffer)
  :hook (prog-mode . format-all-mode))


(use-package treesit-auto
  :ensure t
  :config
  (setq treesit-auto-install t)
  (global-treesit-auto-mode))

;; ============================================================
;; lsp // init // config
;; ============================================================

(use-package rainbow-mode
  :ensure t
  :hook (prog-mode . rainbow-mode))

(use-package lsp-mode
  :ensure t
  :commands lsp lsp-deferred
  :hook ((c-mode . lsp-deferred)
         (c++-mode . lsp-deferred)
         (c-ts-mode . lsp-deferred)
         (c++-ts-mode . lsp-deferred)
         (csharp-ts-mode . lsp-deferred)
         (fsharp-mode . lsp-deferred)
         (haskell-mode . lsp-deferred)
         (haskell-ts-mode . lsp-deferred)
         (python-mode . lsp-deferred)
         (python-ts-mode . lsp-deferred)
         (js-ts-mode . lsp-deferred)
         (tsx-ts-mode . lsp-deferred)
         (typescript-ts-mode . lsp-deferred)
         (nix-mode . lsp-deferred)
         (nix-ts-mode . lsp-deferred))

  :init
  (setq lsp-keymap-prefix "C-c l")

  :config
  (setq lsp-idle-delay 0.5)
  (setq lsp-completion-provider :capf)
  (setq lsp-enable-symbol-highlighting t)
  (setq lsp-enable-snippet nil)
  (setq lsp-headerline-breadcrumb-enable t)
  (setq lsp-modeline-code-actions-enable t)
  (setq lsp-modeline-diagnostics-enable t)
  (setq lsp-log-io nil)

  (add-to-list 'lsp-disabled-clients '(nix-mode . nix-nil))
  (add-to-list 'lsp-disabled-clients '(nix-ts-mode . nix-nil))
  (add-to-list 'lsp-disabled-clients '(nix-mode . rnix-lsp))
  (add-to-list 'lsp-disabled-clients '(nix-ts-mode . rnix-lsp))

  (when (executable-find "nixd")
    (lsp-register-client
     (make-lsp-client :new-connection (lsp-stdio-connection "nixd")
                      :major-modes '(nix-mode nix-ts-mode)
                      :priority 1
                      :server-id 'nixd)))


  (lsp-register-client
   (make-lsp-client :new-connection (lsp-stdio-connection "nixd")
                    :major-modes '(nix-mode nix-ts-mode)
                    :priority 1
                    :server-id 'nixd))

  (setq lsp-auto-guess-root t) ;; auto-detect project roots
  (setq lsp-enable-file-watchers nil) ;; don't ask about watching files
  (setq lsp-enable-suggest-server-download nil) ;; don't prompt to download servers
  )

(use-package lsp-ui
  :ensure t
  :commands lsp-ui-mode
  :hook ((nix-mode . lsp-ui-mode)
         (nix-ts-mode . lsp-ui-mode))

  :config
  (setq lsp-ui-sideline-enable t) ;; sideline in the margin, not inline
  (setq lsp-ui-sideline-show-code-actions nil)
  (setq lsp-ui-sideline-show-symbol nil)

  (setq lsp-ui-sideline-show-diagnostics nil) ;; sideline the diagnostics sideline...
  (setq lsp-ui-sideline-show-hover t) ;; sometimes contains type infosssss....sssss...
  ;; (setq lsp-modeline-diagnostics-enable t)


  ;; keep it subtle
  (setq lsp-ui-sideline-ignore-duplicate t)
  (setq lsp-ui-sideline-delay 1.0)  ; don't flash on every cursor move

  ;; push it to the actual margin
  (setq lsp-ui-sideline-update-mode 'point)  ; only update at point

  ;; doc hover is fine but only on demand
  (setq lsp-ui-doc-enable t)
  (setq lsp-ui-doc-show-with-cursor nil)  ; don't auto-show
  (setq lsp-ui-doc-show-with-mouse nil)   ; don't auto-show

  ;; absolutely no inline hints
  (setq lsp-inlay-hint-enable nil)
  (setq lsp-lens-enable nil))  ; no codelens either, jetbrains is right there if you never ever ever want it...

(use-package consult
  :ensure t
  :bind (("C-c c a" . (lambda ()
                        (interactive)
                        (if (bound-and-true-p lsp-mode)
                            (call-interactively #'lsp-execute-code-action))))

         ("C-c c r" . (lambda ()
                        (interactive)
                        (if (bound-and-true-p lsp-mode)
                            (call-interactively #'lsp-rename)
                          (call-interactively #'eglot-rename))))

         ("C-c c f" . (lambda ()
                        (interactive)
                        (if (bound-and-true-p lsp-mode)
                            (call-interactively #'lsp-format-buffer))))

         ("C-c c d" . eldoc)))

(defun setup-language-tooling (mode)
  (add-hook mode
            (lambda ()
              (lsp-deferred)
              (format-all-mode))))

(mapc #'setup-language-tooling
      '(c-mode-hook
        c++-mode-hook
        c-ts-mode-hook
        c++-ts-mode-hook
        csharp-ts-mode-hook
        fsharp-mode-hook
        haskell-mode-hook
        python-ts-mode-hook
        js-ts-mode-hook
        typescript-ts-mode-hook
        nix-mode-hook))

;; ============================================================
;; flymake // flycheck // subtle
;; ============================================================

;; stop the flycheck bukkake, i don't want new buffers in my face...

(setq flycheck-display-errors-function nil) ;; don't auto-display error buffers
(setq flycheck-help-echo-function nil) ;; don't show errors in echo area either

;; If you still want to see errors on demand:
(defun hypermodern/flycheck-list-errors-only-when-asked ()
  "Only show flycheck errors when explicitly requested."
  (interactive)
  (flycheck-list-errors))

;; Bind it to something reasonable
(global-set-key (kbd "C-c ! l") 'hypermodern/flycheck-list-errors-only-when-asked)

;; Also prevent the error list from stealing focus
(setq flycheck-standard-error-navigation nil)

;; kill the wavy underlines
(custom-set-faces
 '(flymake-error ((t (:underline nil :background nil :foreground nil))))
 '(flymake-warning ((t (:underline nil :background nil :foreground nil))))
 '(flymake-note ((t (:underline nil :background nil :foreground nil))))

 ;; same for `flycheck`
 '(flycheck-error ((t (:underline nil))))
 '(flycheck-warning ((t (:underline nil))))
 '(flycheck-info ((t (:underline nil)))))

;; just use fringe indicators (subtle marks in the gutter)
(setq flymake-fringe-indicator-position 'left-fringe)
(setq flymake-suppress-zero-counters t)
(setq flymake-start-on-flymake-mode t)
(setq flymake-no-changes-timeout 0.5)
(setq flymake-start-on-save-buffer t)
(setq flymake-proc-ignored-file-name-regexps '())

;; Make the fringe marks smaller/subtler
(define-fringe-bitmap 'flymake-double-exclamation-mark
  [#b00000000
   #b00000000
   #b00000000
   #b00001000
   #b00001000
   #b00001000
   #b00001000
   #b00000000])

;; for `flycheck`
(setq flycheck-indication-mode 'left-fringe)
(setq flycheck-highlighting-mode nil) ;; no buffer highlighting at all

;; ============================================================
;; yasnipptet // so global
;; ============================================================

(use-package yasnippet
  :ensure t
  :config
  (yas-global-mode 1))

;; ============================================================
;;                  language // specific
;; ============================================================

;; ============================================================
;; c-sharp // mode
;; ============================================================

(use-package csharp-mode
  :ensure t
  :mode ("\\.cs\\'" . csharp-ts-mode))

;; ============================================================
;; f-sharp // mode
;; ============================================================

(use-package fsharp-mode
  :ensure t
  :mode ("\\.fs[ix]?\\'" . fsharp-mode))

;; ============================================================
;; shell // mode
;; ============================================================

(use-package sh-script
  :mode (("\\.sh\\'" . bash-ts-mode)
         ("\\.bash\\'" . bash-ts-mode)))

;; ============================================================
;; haskell // mode
;; ============================================================

(use-package haskell-mode
  :ensure t
  :mode (("\\.hs\\'" . haskell-mode)
         ("\\.lhs\\'" . literate-haskell-mode)
         ("\\.cabal\\'" . haskell-cabal-mode)
         ("\\.hsc\\'" . haskell-mode))

  :config
  ;; Basic indentation settings
  (setq haskell-indentation-layout-offset 4)
  (setq haskell-indentation-left-offset 4)
  (setq haskell-indentation-where-pre-offset 2)
  (setq haskell-indentation-where-post-offset 2)

  ;; Disable all the legacy interactive stuff - we have LSP
  (setq haskell-tags-on-save nil)
  (setq haskell-stylish-on-save nil)
  (setq haskell-mode-stylish-haskell-path "stylish-haskell")

  ;; Don't load interactive-haskell-mode, it fights with LSP
  (setq haskell-process-type nil)

  :hook
  ((haskell-mode . haskell-indentation-mode)
   (haskell-mode . haskell-decl-scan-mode)))

(use-package lsp-haskell
  :ensure t
  :after (haskell-mode lsp-mode)

  :init
  ;; Clear any competing keybindings before LSP starts
  (add-hook 'haskell-mode-hook
            (lambda ()
              ;; Remove ALL competing bindings
              (local-unset-key (kbd "M-."))
              (local-unset-key (kbd "M-,"))
              (local-unset-key (kbd "C-c C-t")))
            -10) ; Run early with negative priority

  :config
  ;; Use the NixOS-provided HLS
  (setq lsp-haskell-server-path "haskell-language-server-wrapper")

  ;; Modern HLS settings
  (setq lsp-haskell-plugin-stan-global-on nil) ; Stan is noisy
  (setq lsp-haskell-plugin-hlint-global-on t)
  (setq lsp-haskell-plugin-eval-global-on t)
  (setq lsp-haskell-formatting-provider "fourmolu")

  ;; Completions
  (setq lsp-haskell-plugin-ghcide-completions-config-auto-extend-on t)
  (setq lsp-haskell-plugin-ghcide-completions-config-snippets-on t)

  :hook
  (haskell-mode . lsp-deferred))

;; Ensure xref (which backs M-.) is properly configured
(use-package xref
  :ensure nil ; built-in
  :after haskell-mode
  :bind (:map haskell-mode-map
              ("M-." . xref-find-definitions)
              ("M-," . xref-go-back)
              ("M-?" . xref-find-references)))

;; Optional: Better haskell completions
(use-package company-ghci
  :ensure t
  :after (company haskell-mode)
  :config
  ;; Add as fallback only, LSP is primary
  (add-to-list 'company-backends 'company-ghci t))

;; Optional: If you want REPL interaction, use comint directly
(use-package haskell-interactive-mode
  :ensure nil ; part of haskell-mode
  :commands haskell-interactive-switch
  :bind (:map haskell-mode-map
              ("C-c C-z" . haskell-interactive-switch)
              ("C-c C-l" . haskell-process-load-file))
  :config
  ;; If loaded, don't let it mess with navigation
  (when (boundp 'haskell-interactive-mode-map)
    (define-key haskell-interactive-mode-map (kbd "M-.") nil)
    (define-key haskell-interactive-mode-map (kbd "M-,") nil)))

;; ============================================================
;; nix // mode
;; ============================================================

(use-package nix-mode
  :ensure t
  :mode "\\.nix\\'"
  :config

  (setq lsp-nix-nixd-server-path "nixd")

  (setq lsp-nix-nixd-formatting-command [ "nixfmt" ])
  (setq lsp-nix-nixd-nixpkgs-expr "import <nixpkgs> { }")
  (setq lsp-nix-nixd-nixos-options-expr "(let pkgs = import \"${inputs.nixpkgs}\" { }; in (pkgs.lib.evalModules { modules =  (import \"${inputs.nixpkgs}/nixos/modules/module-list.nix\") ++ [ ({...}: { nixpkgs.hostPlatform = builtins.currentSystem;} ) ] ; })).options")
  (setq lsp-nix-nixd-home-manager-options-expr "(let pkgs = import \"${inputs.nixpkgs}\" { }; lib = import \"${inputs.home-manager}/modules/lib/stdlib-extended.nix\" pkgs.lib; in (lib.evalModules { modules =  (import \"${inputs.home-manager}/modules/modules.nix\") { inherit lib pkgs; check = false; }; })).options"))

;; ============================================================
;; ts // js // mode
;; ============================================================

(use-package typescript-ts-mode
  :ensure nil
  :mode (("\\.ts\\'" . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode)
         ("\\.js\\'" . js-ts-mode)
         ("\\.jsx\\'" . jsx-ts-mode))

  :config
  ;; Always use 2 spaces
  (setq typescript-ts-mode-indent-offset 2)
  (setq js-ts-mode-indent-offset 2)
  (setq js-indent-level 2)
  (setq typescript-indent-level 2)

  ;; Nuclear biome formatter for these modes
  (defun hypermodern/biome-format-2-spaces ()
    "Force Biome to format with 2-space indentation, no exceptions."
    (interactive)
    (let* ((file (or (buffer-file-name) "file.js"))
           (content (buffer-substring-no-properties (point-min) (point-max)))
           (output-buffer (generate-new-buffer " *biome-format*"))
           (orig-buffer (current-buffer))
           (orig-point (point))  ; Save cursor position
           (orig-window-start (window-start)))  ; Save scroll position
      (with-current-buffer output-buffer
        (insert content)
        (if (zerop (call-process-region (point-min) (point-max)
                                        "biome" t t nil
                                        "format"
                                        "--stdin-file-path" file
                                        "--indent-width=2"
                                        "--indent-style=space"))
            (let ((formatted (buffer-string)))
              (kill-buffer output-buffer)
              (with-current-buffer orig-buffer
                (erase-buffer)
                (insert formatted)
                (goto-char (min orig-point (point-max)))  ; Restore cursor
                (set-window-start (selected-window) orig-window-start t)  ; Restore scroll
                (message "[biome] formatted with 2 spaces")))
          (kill-buffer output-buffer)
          (message "[biome] formatting failed")))))

  :hook
  ((typescript-ts-mode js-ts-mode tsx-ts-mode) .
   (lambda ()
     ;; Force all indentation settings
     (setq-local tab-width 2)
     (setq-local indent-tabs-mode nil)
     (setq-local js-indent-level 2)
     (setq-local typescript-indent-level 2)
     (setq-local standard-indent 2)

     ;; NUCLEAR OVERRIDE: Hijack M-z for these modes only
     (local-set-key (kbd "M-z") 'hypermodern/biome-format-2-spaces)

     ;; Also override any format-all binding
     (local-set-key (kbd "C-c C-f") 'hypermodern/biome-format-2-spaces)

     ;; Kill any other formatting functions
     (setq-local format-all-formatters nil)
     (when (fboundp 'format-all-mode)
       (format-all-mode -1)))))

;; Also handle the non-tree-sitter variants
(use-package js-mode
  :ensure nil
  :hook
  ((js-mode javascript-mode) .
   (lambda ()
     (setq-local tab-width 2)
     (setq-local indent-tabs-mode nil)
     (setq-local js-indent-level 2)
     (local-set-key (kbd "M-z") 'hypermodern/biome-format-2-spaces))))

(use-package typescript-mode
  :ensure t
  :hook
  (typescript-mode .
                   (lambda ()
                     (setq-local tab-width 2)
                     (setq-local indent-tabs-mode nil)
                     (setq-local typescript-indent-level 2)
                     (local-set-key (kbd "M-z") 'hypermodern/biome-format-2-spaces))))

;; ============================================================
;; rust // mode
;; ============================================================

(use-package rust-ts-mode
  :ensure nil
  :mode (("\\.rs\\'" . rust-ts-mode))
)

;; ============================================================
;; python // mode
;; ============================================================

(use-package lsp-pyright
  :ensure t
  :demand t
  :after lsp-mode
  :custom
  (lsp-pyright-typechecking-mode "strict")
  (lsp-pyright-diagnostic-mode "workspace")

  :config
  (setq lsp-pyright-venv-strategy "useBestEffort")
  (setq lsp-pyright-basedpyright-inlay-hints nil) ; keep it clean

  ;; n.b. increase heap size for the `python` language server...
  (setenv "NODE_OPTIONS" "--max-old-space-size=16384") ; 16GB
  (setq lsp-pyright-langserver-command-args
        '("--stdio"
          "--max-old-space-size=8192"  ; 8GB heap
          "--max-semi-space-size=1024")) ; 1GB for garbage collection
  
  ;; Alternative: If using node directly
  (setq lsp-pyright-python-executable-cmd "python")
  (setq lsp-pyright-server-command
        '("node" "--max-old-space-size=8192" 
          "/path/to/pyright-langserver" "--stdio"))
  
  :hook
  ((python-mode . lsp-deferred)
   (python-ts-mode . lsp-deferred)))

;; ============================================================
;; shell / sh-mode
;; ============================================================

(use-package sh-mode
  :ensure nil
  :mode (("\\.sh\\'" . sh-mode)
         ("\\.bash\\'" . sh-mode)
         ("\\.zsh\\'" . sh-mode))
  :config
  (setq sh-basic-offset 2
        sh-indentation 2
        sh-indent-for-case-label 0
        sh-indent-for-case-alt '+)
  :hook
  (sh-mode . (lambda () (setq indent-tabs-mode nil))))

;; If you're using tree-sitter bash mode
(use-package bash-ts-mode
  :ensure nil
  :mode (("\\.sh\\'" . bash-ts-mode)
         ("\\.bash\\'" . bash-ts-mode))

  :when (treesit-available-p)

  :config

  (setq sh-basic-offset 2)
  :hook
  (bash-ts-mode . (lambda () (setq indent-tabs-mode nil))))

(provide 'init)
;;; init.el ends here
