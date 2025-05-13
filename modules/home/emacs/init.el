;;; init.el --- -*- lexical-binding: t -*-
;;
;; "On The Design Of Text Editors" - https://arxiv.org/abs/2008.06030
;;
;;
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

(defvar hyper-modern/gc-cons-threshold (* 256 1024 1024))

(setq
 gc-cons-threshold hyper-modern/gc-cons-threshold
 gc-cons-percentage 0.1)

(add-hook
 'minibuffer-setup-hook
 (lambda ()
   (setq gc-cons-threshold most-positive-fixnum)))

(add-hook
 'minibuffer-exit-hook
 (lambda ()
   (garbage-collect)
   (setq gc-cons-threshold hyper-modern/gc-cons-threshold)))

(setq copy-region-blink-delay 0)

;; ============================================================
;; package management
;; ============================================================

(setq native-comp-async-report-warnings-errors nil)

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Bootstrap use-package
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

;; ============================================================
;; ui // reinit
;; ============================================================

(setq inhibit-startup-screen t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(setq frame-title-format "// %b //")

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

(defun remove-bold-italic-from-all-faces ()
  "Remove all bold and italic attributes from all faces."
  (mapc (lambda (face)
          (when (face-attribute face :weight nil t)
            (set-face-attribute face nil :weight 'normal))
          (when (face-attribute face :slant nil t)
            (set-face-attribute face nil :slant 'normal)))
        (face-list)))

(remove-bold-italic-from-all-faces)

;; ============================================================
;; hyper // modern // interactive
;; ============================================================

(defun hyper-modern/reinit-vertical-divider (&optional sync-with-mode-line)
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
     (make-glyph-code ?│)))

  ;; Optional mode-line syncing
  (when sync-with-mode-line
    (hyper-modern/sync-divider-with-mode-line)))

(defun hyper-modern/sync-divider-with-mode-line ()
  "Sync vertical border color with mode-line background.
Can be called independently or by hyper-modern/reinit-vertical-divider."
  (interactive)
  (let ((bg (face-background 'mode-line)))
    (when bg
      (set-face-foreground 'vertical-border bg))))

;; Optional: Enable automatic syncing when themes change
(defun hyper-modern/enable-auto-divider-sync ()
  "Enable automatic syncing of divider with mode-line when themes change."
  (interactive)
  (advice-add 'load-theme :after
              (lambda (&rest _) (hyper-modern/sync-divider-with-mode-line))))

(defun hyper-modern/disable-auto-divider-sync ()
  "Disable automatic syncing of divider with mode-line."
  (interactive)
  (advice-remove 'load-theme #'hyper-modern/sync-divider-with-mode-line))

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

  (setq gptel-max-tokens 200000        ;Maximum input tokens (200K)
        gptel-response-length 4096)    ;Maximum output tokens (4K)

  (setq gptel-backend
        (gptel-make-anthropic "sonnet-3.7"
          :stream t
          :key #'gptel-api-key-from-auth-source
          :models '(claude-3-7-sonnet-20250219)
          :request-params '(:max_tokens 4096)))

  ;; OpenAI GPT-4o
  (gptel-make-openai "gpt-4o"
    :stream t
    :key #'gptel-api-key-from-auth-source
    :models '(gpt-4o-2024-05-13)
    :request-params '(:max_tokens 4096))

  ;; DeepSeek
  (gptel-make-deepseek "deepseek"
    :stream t
    :key (or (getenv "GPTEL_DEEPSEEK_KEY")
             #'gptel-api-key-from-netrc)
    :models '(deepseek-coder deepseek-chat)
    :request-params '(:max_tokens 4096))

  (setq gptel-model 'claude-3-7-sonnet-20250219))

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

  :custom
  (vertico-cycle t)

  :init
  (vertico-mode)
  (vertico-reverse-mode)
  )

(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless))
  (completion-category-defaults nil)
  (completion-category-overrides '((command (styles orderless))))
  )

(use-package posframe
  :ensure t)

(use-package marginalia
  :ensure t
  :init
  (marginalia-mode)
  :bind (:map minibuffer-local-map ("M-A" . marginalia-cycle))
  )

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

(defun hyper-modern/scratch ()
  (let ((dir (if buffer-file-name
	         (file-name-directory buffer-file-name)
               default-directory)))
    (get-buffer-create (concat dir "elisp-scratch.el"))))

(defun hyper-modern/other ()
  (let ((buf (other-buffer (current-buffer))))
    (if (or (null buf) (eq buf (current-buffer)))
        (hyper-modern/scratch)
      buf)))

(defun hyper-modern/switch ()
  (let ((nw (next-window))
        (cb (current-buffer)))
    (with-selected-window nw
      (when (eq (window-buffer) cb)
        (switch-to-buffer (hyper-modern/other))))))

(defun hyper-modern/hsplit (&optional size)
  (interactive)
  (split-window-right size)
  (hyper-modern/switch))

(defun hyper-modern/vsplit (&optional size)
  (interactive)
  (split-window-below size)
  (hyper-modern/switch))

(defun hyper-modern/rotate-windows ()
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

(defun hyper-modern/magit-display-buffer-function (buffer)
  "Display BUFFER in the rightmost window without splitting."
  (let ((window (if (one-window-p)
                    (selected-window)
                  (window-at (- (frame-width) 2) 1))))
    (select-window window)
    (set-window-buffer window buffer)
    window))

(use-package magit
  :ensure t
  :config
  (setq magit-display-buffer-function #'hyper-modern/magit-display-buffer-function))

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

(use-package dashboard
  :ensure t
  :config
  (defvar my-custom-banner-file (make-temp-file "emacs-dashboard-banner-" nil ".txt"))
  (defvar my-custom-banner-text "HYPER // MODERN // NIX ")

  (with-temp-file my-custom-banner-file
    (insert my-custom-banner-text))

  (setq dashboard-startup-banner my-custom-banner-file)

  (setq dashboard-banner-logo-title
        "it was the style that mattered and the style was the same.
the moderns were mercenaries, practical jokers, nihilistic tehcnofetishists.")

  (setq dashboard-center-content t)

  (setq dashboard-set-heading-icons t)

  (setq dashboard-set-file-icons t)

  (setq dashboard-items '((projects . 5)
                          (recents . 5)))

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

  (defun hyper-modern/what-face (pos)
    "Display the face at POS."
    (interactive "d")
    (let ((face (or (get-char-property (point) 'read-face-name)
                    (get-char-property (point) 'face))))
      (if face (message "Face: %s" face) (message "No face at %d" pos))))

  (defun hyper-modern/show-current-file ()
    "Print the current buffer filename to the minibuffer."
    (interactive)
    (message (buffer-file-name)))

  (defun hyper-modern/kill-current-buffer ()
    "Kill the current buffer."
    (interactive)
    (kill-buffer (current-buffer)))

  (defun hyper-modern/visit-init-file ()
    (interactive)
    (find-file user-init-file))

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
   "M-i"     'hyper-modern/visit-init-file
   "M-z"     'format-all-buffer

   ;; `hyper-modern` overrides
   "C-M-r"   'consult-ripgrep
   "M-R"     'hyper-modern/rotate-windows
   "C-c f"   'hyper-modern/show-current-file
   "C-x 2"   'hyper-modern/vsplit
   "C-x 3"   'hyper-modern/hsplit
   "C-x k"   'hyper-modern/kill-current-buffer))

;; ============================================================
;; FORMATTING CONFIGURATION
;; ============================================================

;; Disable native-comp warnings for undefined functions
(setq native-comp-async-report-warnings-errors nil)

;; Function to disable LSP formatters to avoid conflicts
(defun disable-lsp-formatters ()
  (when (and (boundp 'eglot--managed-mode) eglot--managed-mode)
    (remove-hook 'before-save-hook #'eglot-format-buffer t)))

;; Function to check if a command exists in PATH
(defun command-exists-p (command)
  "Check if COMMAND exists and is executable."
  (and command
       (not (string-empty-p command))
       (eq 0 (call-process-shell-command (concat "command -v " (shell-quote-argument command)) nil nil nil))))

;; Base formatter
(use-package format-all
  :ensure t
  :bind ("M-z" . format-all-buffer)
  :config

  :hook (prog-mode . format-all-mode)  ;; Enable format-all in all programming modes

  ;; Configure available formatters with NixOS-friendly commands
  (setq format-all-default-formatters
        '(("C"            . clang-format)
          ("C++"          . clang-format)
          ("C#"           . clang-format)
          ("CSS"          . prettier)
          ("F#"           . fantomas)
          ("Go"           . gofmt)
          ("HTML"         . prettier)
          ("Haskell"      . brittany)
          ("JavaScript"   . biome)
          ("JSON"         . biome)
          ("Markdown"     . mdformat)
          ("Nix"          . nixfmt)
          ("Python"       . ruff)
          ("Ruby"         . rubocop)
          ("Rust"         . rustfmt)
          ("Shell"        . shfmt)
          ("TypeScript"   . biome)
          ("TSX"          . biome)
          ("YAML"         . yamlfmt)
          ("TOML"         . taplo)
          ("Terraform"    . terraform)
          ("HCL"          . hclfmt)
          ("Zig"          . zig)))

  (add-hook 'format-all-mode-hook #'disable-lsp-formatters))

;; TreeSit configuration
(use-package treesit
  :config
  (setq treesit-language-source-alist
        '((bash "https://github.com/tree-sitter/tree-sitter-bash")
          (c "https://github.com/tree-sitter/tree-sitter-c")
          (c-sharp "https://github.com/tree-sitter/tree-sitter-c-sharp")
          (cpp "https://github.com/tree-sitter/tree-sitter-cpp")
          (css "https://github.com/tree-sitter/tree-sitter-css")
          (go "https://github.com/tree-sitter/tree-sitter-go")
          (html "https://github.com/tree-sitter/tree-sitter-html")
          (javascript "https://github.com/tree-sitter/tree-sitter-javascript")
          (json "https://github.com/tree-sitter/tree-sitter-json")
          (nix "https://github.com/nix-community/tree-sitter-nix")
          (python "https://github.com/tree-sitter/tree-sitter-python")
          (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
          (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
          (yaml "https://github.com/ikatyang/tree-sitter-yaml")
          (ruby "https://github.com/tree-sitter/tree-sitter-ruby")
          (toml "https://github.com/tree-sitter/tree-sitter-toml")
          (zig "https://github.com/maxxnino/tree-sitter-zig"))))

(use-package treesit-auto
  :ensure t
  :config
  (global-treesit-auto-mode))

(setq auto-mode-alist
      (append '(("\\.c\\'" . c-ts-mode)
                ("\\.h\\'" . c++-ts-mode)
                ("\\.cpp\\'" . c++-ts-mode)
                ("\\.hpp\\'" . c++-ts-mode)
                ("\\.cs\\'" . csharp-ts-mode)
                ("\\.fs[ix]?\\'" . fsharp-mode)
                ("\\.hs\\'" . haskell-mode)
                ("\\.py\\'" . python-ts-mode)
                ("\\.js\\'" . js-ts-mode)
                ("\\.jsx\\'" . jsx-ts-mode)
                ("\\.ts\\'" . typescript-ts-mode)
                ("\\.tsx\\'" . tsx-ts-mode)
                ("\\.json\\'" . json-ts-mode)
                ("\\.nix\\'" . nix-mode)
                ("\\.sh\\'" . bash-ts-mode))
              auto-mode-alist))

;; ============================================================
;; LSP Configuration
;; ============================================================

;; Common configuration for both language server frameworks
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
  ;; LSP performance adjustments
  (setq lsp-idle-delay 0.5)
  (setq lsp-completion-provider :capf)
  (setq lsp-enable-symbol-highlighting t)
  (setq lsp-enable-snippet nil)
  (setq lsp-headerline-breadcrumb-enable t)
  (setq lsp-modeline-code-actions-enable t)
  (setq lsp-modeline-diagnostics-enable t)
  (setq lsp-log-io nil)

  ;; Nix LSP settings
  (add-to-list 'lsp-disabled-clients '(nix-mode . nix-nil))
  (add-to-list 'lsp-disabled-clients '(nix-ts-mode . nix-nil))
  (add-to-list 'lsp-disabled-clients '(nix-mode . rnix-lsp))
  (add-to-list 'lsp-disabled-clients '(nix-ts-mode . rnix-lsp))

  ;; Register nixd
  (lsp-register-client
   (make-lsp-client :new-connection (lsp-stdio-connection "nixd")
                    :major-modes '(nix-mode nix-ts-mode)
                    :priority 1
                    :server-id 'nixd)))

;; LSP UI for Nix modes
(use-package lsp-ui
  :ensure t
  :commands lsp-ui-mode
  :hook ((nix-mode . lsp-ui-mode)
         (nix-ts-mode . lsp-ui-mode))

  :config
  (setq lsp-ui-doc-enable t)
  (setq lsp-ui-doc-position 'at-point)
  (setq lsp-ui-sideline-enable t)
  (setq lsp-ui-sideline-show-diagnostics t)
  (setq lsp-ui-sideline-show-hover t)
  (setq lsp-ui-sideline-show-code-actions t))

;; Enhanced completion with Corfu - works with both
(use-package corfu
  :ensure t

  :init
  (global-corfu-mode)

  :config
  (setq corfu-auto t
        corfu-auto-delay 0.2
        corfu-auto-prefix 2
        corfu-cycle t
        corfu-preselect 'prompt))

;; Shared key bindings for both frameworks
(use-package consult
  :ensure t
  :bind (("C-c c a" . #'(lambda ()
                          (interactive)
                          (if (bound-and-true-p lsp-mode)
                              (call-interactively #'lsp-execute-code-action)
                            (call-interactively #'eglot-code-actions))))

         ("C-c c r" . #'(lambda ()
                          (interactive)
                          (if (bound-and-true-p lsp-mode)
                              (call-interactively #'lsp-rename)
                            (call-interactively #'eglot-rename))))

         ("C-c c f" . #'(lambda ()
                          (interactive)
                          (if (bound-and-true-p lsp-mode)
                              (call-interactively #'lsp-format-buffer)
                            (call-interactively #'eglot-format))))

         ("C-c c d" . eldoc)))

(defun setup-language-tooling (mode)
  "Set up formatting and LSP for a specific mode."
  (add-hook mode
            (lambda ()
              (lsp-deferred)
              (format-all-mode)
              (add-hook 'before-save-hook #'format-all-buffer nil t))))

;; Apply to all modes you want both LSP and format-all
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
;; Snippets with YASnippet
;; ============================================================

(use-package yasnippet
  :ensure t
  :config
  (yas-global-mode 1))

;; ============================================================
;; Language-specific configurations
;; ============================================================

;; ============================================================
;; C/C++ specific configuration
;; ============================================================

;; C# Mode
;; ============================================================

(use-package csharp-mode
  :ensure t
  :mode ("\\.cs\\'" . csharp-ts-mode))

;; F# Mode
;; ============================================================

(use-package fsharp-mode
  :ensure t
  :mode ("\\.fs[ix]?\\'" . fsharp-mode))

;; Bash/Shell Mode
;; ============================================================

(use-package sh-script
  :mode (("\\.sh\\'" . bash-ts-mode)
         ("\\.bash\\'" . bash-ts-mode)))

;; Nix Mode
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


;; TypeScript/JavaScript Mode
;; ============================================================

(use-package typescript-ts-mode
  :ensure nil
  :mode (("\\.ts\\'" . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode)
         ("\\.js\\'" . js-ts-mode)
         ("\\.jsx\\'" . jsx-ts-mode))
  :config
  (setq typescript-ts-mode-indent-offset 2)
  (setq js-ts-mode-indent-offset 2))

;; Python Mode
;; ============================================================

(use-package python-ts-mode
  :ensure nil
  :mode (("\\.py\\'" . python-ts-mode)
         ("\\.pyi\\'" . python-ts-mode)))

;; ============================================================
;; Completion with Company
;; ============================================================

(use-package company
  :ensure t
  :bind (("M-TAB" . company-complete-common-or-cycle)
         ("C-M-i" . company-complete-common-or-cycle))

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
  (setq company-require-match nil))


(provide 'init)
;;; init.el ends here
