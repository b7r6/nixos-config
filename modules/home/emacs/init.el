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

(require 'cl-lib)
(require 'seq)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                      // memory // performance // optimization
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defvar hypermodern--file-name-handler-alist file-name-handler-alist)

(setq file-name-handler-alist nil
      gc-cons-threshold most-positive-fixnum)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist hypermodern--file-name-handler-alist
                  gc-cons-threshold (* 128 1024 1024))))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;             // early frame seeding // prevent PGTK pink flash
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(setq default-frame-alist
      '((background-color . "#111417")
        (foreground-color . "#d8e0e7")
        (vertical-scroll-bars . nil)
        (horizontal-scroll-bars . nil)
        (internal-border-width . 0)
        (left-fringe . 8)
        (right-fringe . 8)))

(setq initial-frame-alist default-frame-alist)

;; disable gtk tooltips (cause color issues on PGTK)
(setq x-gtk-use-system-tooltips nil)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // package loading (straight.el + Nix hybrid)
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;
;; Portable config: works on NixOS (packages preloaded) and vanilla emacs.
;; - On Nix: packages are preloaded, straight.el available for extras
;; - On vanilla: straight.el fetches everything
;;

;; Detect if we're running under Nix-managed emacs with packages
(defvar hypermodern/nix-emacs-p
  (and (getenv "NIX_PROFILES")
       (locate-library "vertico"))  ; test for a Nix-provided package
  "Non-nil if running Nix-managed Emacs with preloaded packages.")

;; Bootstrap straight.el (always available for ad-hoc packages)
;; Suppress warning about package.el - we intentionally use both:
;; - package.el for Nix-provided packages (autoloads)
;; - straight.el for additional packages not in Nix
(setq straight-package--warning-displayed t)
(defvar bootstrap-version)

(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el"
                         (or (getenv "EMACSDIR") user-emacs-directory)))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; integrate `straight.el` with `use-package`
(straight-use-package 'use-package)

;; Configure use-package + straight.el behavior
;; - On Nix: packages preloaded, straight available but won't auto-fetch
;; - On vanilla: straight fetches packages automatically

(if hypermodern/nix-emacs-p
    (setq straight-use-package-by-default nil
          use-package-always-ensure nil)

  (setq straight-use-package-by-default t
        use-package-always-ensure nil))

(setq
 use-package-verbose nil
 use-package-expand-minimally t)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                    // forward // declarations
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

;; External package functions
(declare-function eglot-format-buffer "eglot" ())
(declare-function eglot-rename "eglot" ())
(declare-function vertico-reverse-mode "vertico" (&optional arg))
(declare-function vertico-mode "vertico" (&optional arg))
(declare-function dimmer-mode "dimmer" (&optional arg))
(declare-function format-all-buffer "format-all" (formatter))
(declare-function popper-mode "popper" (&optional arg))
(declare-function marginalia-mode "marginalia" (&optional arg))
(declare-function company-complete "company" ())
(declare-function global-clipetty-mode "clippety" (&optional arg))
(declare-function yas-global-mode "yasnippet" (&optional arg))
(declare-function global-treesit-auto-mode "treesit-auto" (&optional arg))
(declare-function lsp-register-client "lsp-mode" (client))
(declare-function make-lsp-client "lsp-mode" (&rest plist))
(declare-function lsp-stdio-connection "lsp-mode" (command))
(declare-function tramp-cleanup-all-connections "tramp" ())
(declare-function tramp-cleanup-all-buffers "tramp" ())
(declare-function password-store-dir "password-store" ())
(declare-function password-store--file-to-entry "password-store" (file))
(declare-function auth-source-pass-enable "auth-source-pass" ())
(declare-function ffap-file-at-point "ffap" ())
(declare-function general-define-key "general" (&rest maps))
(declare-function direnv-mode "direnv" (&optional arg))
(declare-function dashboard-setup-startup-hook "dashboard" ())
(declare-function color-rgb-to-hex "color" (red green blue &optional digits-per-component))
(declare-function flymake-mode "flymake" (&optional arg))

;; External package variables
(defvar lean4-mode-map)
(defvar lsp-completion-provider)
(defvar lsp-diagnostics-provider)
(defvar lsp-lens-enable)
(defvar lsp-diagnostics-attributes)
(defvar lsp-ui-sideline-show-diagnostics)
(defvar lsp-ui-sideline-show-code-actions)
(defvar ansi-color-names-vector)
(defvar doom-modeline-height)
(defvar doom-modeline-icon)
(defvar doom-modeline-major-mode-icon)
(defvar doom-modeline-minor-modes)
(defvar doom-modeline-buffer-encoding)
(defvar doom-modeline-checker-simple-format)
(defvar doom-modeline-modal)
(defvar dimmer-fraction)
(defvar tramp-use-ssh-controlmaster-options)

;; Functions defined later in this file
(declare-function hypermodern/visit-init "init" ())
(declare-function hypermodern/goto-definition-or-file "init" ())
(declare-function hypermodern/kill-buffer "init" ())
(declare-function hypermodern/format-buffer "init" ())

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                          // PGTK // detection
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defvar hypermodern/is-pgtk
  (and (boundp 'system-configuration-features)
       (string-match-p "PGTK" system-configuration-features))
  "Non-nil if running on PGTK build of Emacs.")

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                         // theme engine // zero depdendencies
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defvar hypermodern/palettes
  '((ono-sendai-razorgirl
     :name "Ono-Sendai Razorgirl"
     :variant dark
     :base00 "#111417"  :base01 "#181c21"  :base02 "#21262d"  :base03 "#2b323a"
     :base04 "#596775"  :base05 "#d8e0e7"  :base06 "#ddf4ff"  :base07 "#e6f7ff"
     :base08 "#b6e3ff"  :base09 "#80ccff"  :base0A "#54aeff"  :base0B "#218bff"
     :base0C "#0969da"  :base0D "#4d9fff"  :base0E "#6cb6ff"  :base0F "#1f6feb")

    (ono-sendai-tuned
     :name "Ono-Sendai HSL Tuned"
     :variant dark
     :base00 "#191c20"  :base01 "#1f232a"  :base02 "#2a3039"  :base03 "#3a424f"
     :base04 "#6b7689"  :base05 "#c5d0dd"  :base06 "#dce3ec"  :base07 "#f0f4f8"
     :base08 "#b6e3ff"  :base09 "#80ccff"  :base0A "#54aeff"  :base0B "#218bff"
     :base0C "#0969da"  :base0D "#4d9fff"  :base0E "#6cb6ff"  :base0F "#1f6feb")

    (ono-sendai-chiba
     :name "Ono-Sendai Chiba"
     :variant dark
     :base00 "#090b0e"  :base01 "#13161a"  :base02 "#1a1f24"  :base03 "#23292f"
     :base04 "#596775"  :base05 "#d8e0e7"  :base06 "#ddf4ff"  :base07 "#e6f7ff"
     :base08 "#b6e3ff"  :base09 "#80ccff"  :base0A "#54aeff"  :base0B "#218bff"
     :base0C "#0969da"  :base0D "#4d9fff"  :base0E "#6cb6ff"  :base0F "#1f6feb")

    (ono-sendai-memphis
     :name "Ono-Sendai Memphis"
     :variant dark
     :base00 "#000000"  :base01 "#0a0d10"  :base02 "#13161a"  :base03 "#1a1f24"
     :base04 "#596775"  :base05 "#d8e0e7"  :base06 "#ddf4ff"  :base07 "#e6f7ff"
     :base08 "#b6e3ff"  :base09 "#80ccff"  :base0A "#54aeff"  :base0B "#218bff"
     :base0C "#0969da"  :base0D "#4d9fff"  :base0E "#6cb6ff"  :base0F "#1f6feb")

    (ono-sendai-sprawl
     :name "Ono-Sendai Sprawl"
     :variant dark
     :base00 "#191c20"  :base01 "#1f232a"  :base02 "#2a3039"  :base03 "#3a424f"
     :base04 "#596775"  :base05 "#d8e0e7"  :base06 "#ddf4ff"  :base07 "#e6f7ff"
     :base08 "#b6e3ff"  :base09 "#80ccff"  :base0A "#54aeff"  :base0B "#218bff"
     :base0C "#0969da"  :base0D "#4d9fff"  :base0E "#6cb6ff"  :base0F "#1f6feb")

    (ono-sendai-github
     :name "Ono-Sendai GitHub"
     :variant dark
     :base00 "#22272e"  :base01 "#2d333b"  :base02 "#444c56"  :base03 "#545d68"
     :base04 "#596775"  :base05 "#d8e0e7"  :base06 "#ddf4ff"  :base07 "#e6f7ff"
     :base08 "#b6e3ff"  :base09 "#80ccff"  :base0A "#54aeff"  :base0B "#218bff"
     :base0C "#0969da"  :base0D "#4d9fff"  :base0E "#6cb6ff"  :base0F "#1f6feb")

    (ono-sendai-spectrum
     :name "Ono-Sendai Spectrum"
     :variant dark
     :base00 "#191c20"  :base01 "#1f232a"  :base02 "#2a3039"  :base03 "#3a424f"
     :base04 "#6b7689"  :base05 "#c5d0dd"  :base06 "#dce3ec"  :base07 "#f0f4f8"
     :base08 "#b6e3ff"  :base09 "#7dd3ff"  :base0A "#54aeff"  :base0B "#4eb8ff"
     :base0C "#47c0ff"  :base0D "#5ba3ff"  :base0E "#6c95ff"  :base0F "#1f6feb")

    (ono-sendai-untuned
     :name "Ono-Sendai Untuned"
     :variant dark
     :base00 "#090b0e"  :base01 "#13161a"  :base02 "#1a1f24"  :base03 "#23292f"
     :base04 "#23292f"  :base05 "#d8e0e7"  :base06 "#596775"  :base07 "#ddf4ff"
     :base08 "#b6e3ff"  :base09 "#80ccff"  :base0A "#54aeff"  :base0B "#218bff"
     :base0C "#0969da"  :base0D "#54aeff"  :base0E "#80ccff"  :base0F "#218bff")

    (maas-neoform
     :name "Maas Neoform"
     :variant light
     :base00 "#f5f7fa"  :base01 "#e8ecf2"  :base02 "#d4dbe6"  :base03 "#8896a8"
     :base04 "#5c6b7d"  :base05 "#2d3848"  :base06 "#1d2530"  :base07 "#0f1318"
     :base08 "#0550ae"  :base09 "#0969da"  :base0A "#1f6feb"  :base0B "#218bff"
     :base0C "#54aeff"  :base0D "#0550ae"  :base0E "#0969da"  :base0F "#1b4b91")

    (maas-bioptic
     :name "Maas Bioptic"
     :variant light
     :base00 "#faf8f5"  :base01 "#f0ece5"  :base02 "#e2dcd2"  :base03 "#8a8378"
     :base04 "#5c574e"  :base05 "#33302a"  :base06 "#201e1a"  :base07 "#121110"
     :base08 "#0550ae"  :base09 "#0969da"  :base0A "#1f6feb"  :base0B "#218bff"
     :base0C "#54aeff"  :base0D "#0550ae"  :base0E "#0969da"  :base0F "#6e5494")

    (maas-ghost
     :name "Maas Ghost"
     :variant light
     :base00 "#e8ecf0"  :base01 "#dce2e9"  :base02 "#c8d1dc"  :base03 "#7a8a9c"
     :base04 "#556270"  :base05 "#384452"  :base06 "#252e38"  :base07 "#151a20"
     :base08 "#3272b5"  :base09 "#4080c4"  :base0A "#4d8fd4"  :base0B "#5a9de3"
     :base0C "#6aabef"  :base0D "#3272b5"  :base0E "#4080c4"  :base0F "#5c6e85")

    (maas-tessier
     :name "Maas Tessier-Ashpool"
     :variant light
     :base00 "#ffffff"  :base01 "#f0f3f6"  :base02 "#d8e0e8"  :base03 "#6b7a8a"
     :base04 "#424d5b"  :base05 "#1a2028"  :base06 "#0d1117"  :base07 "#000000"
     :base08 "#0349b4"  :base09 "#0758c9"  :base0A "#0066e0"  :base0B "#0078ff"
     :base0C "#2090ff"  :base0D "#0349b4"  :base0E "#0758c9"  :base0F "#7c3aed"))
  "All hypermodern theme palettes.")

(defvar hypermodern/current-theme 'ono-sendai-sprawl)

(defun hypermodern/get-palette (theme-name)
  (cdr (assq theme-name hypermodern/palettes)))

(defun hypermodern/theme-variant (theme-name)
  (plist-get (hypermodern/get-palette theme-name) :variant))

(defun hypermodern/dark-themes ()
  (seq-filter (lambda (name) (eq 'dark (hypermodern/theme-variant name)))
              (mapcar #'car hypermodern/palettes)))

(defun hypermodern/light-themes ()
  (seq-filter (lambda (name) (eq 'light (hypermodern/theme-variant name)))
              (mapcar #'car hypermodern/palettes)))

(defun hypermodern/generate-faces (palette)
  "Generate face specs from PALETTE."
  (let ((bg      (plist-get palette :base00))
        (bg-alt  (plist-get palette :base01))
        (bg-hl   (plist-get palette :base02))
        (comment (plist-get palette :base03))
        (fg-alt  (plist-get palette :base04))
        (fg      (plist-get palette :base05))
        (fg-light (plist-get palette :base06))
        (_white   (plist-get palette :base07))
        (ice     (plist-get palette :base08))
        (sky     (plist-get palette :base09))
        (hero    (plist-get palette :base0A))
        (deep    (plist-get palette :base0B))
        (matrix  (plist-get palette :base0C))
        (link    (plist-get palette :base0D))
        (soft    (plist-get palette :base0E))
        (corp    (plist-get palette :base0F))
        (class '((class color) (min-colors 89))))

    `((default ((,class (:foreground ,fg :background ,bg))))
      (cursor ((,class (:background ,hero))))
      (region ((,class (:background ,bg-hl :extend t))))
      (highlight ((,class (:background ,bg-hl))))
      (hl-line ((,class (:background ,bg-alt :extend t))))
      (fringe ((,class (:background ,bg))))
      (vertical-border ((,class (:foreground ,bg-hl))))
      (border ((,class (:background ,bg-hl))))
      (secondary-selection ((,class (:background ,bg-hl))))
      (minibuffer-prompt ((,class (:foreground ,hero :weight bold))))
      (tooltip ((,class (:foreground ,fg :background ,bg-alt))))
      (shadow ((,class (:foreground ,comment))))
      (match ((,class (:background ,bg-hl :foreground ,hero :weight bold))))
      (internal-border ((,class (:background ,bg))))
      (child-frame-border ((,class (:background ,bg-hl))))
      (window-divider ((,class (:foreground ,bg-hl))))
      (window-divider-first-pixel ((,class (:foreground ,bg-hl))))
      (window-divider-last-pixel ((,class (:foreground ,bg-hl))))

      ;; Font lock
      (font-lock-builtin-face ((,class (:foreground ,matrix))))
      (font-lock-comment-face ((,class (:foreground ,comment))))
      (font-lock-comment-delimiter-face ((,class (:foreground ,comment))))
      (font-lock-doc-face ((,class (:foreground ,fg-alt))))
      (font-lock-constant-face ((,class (:foreground ,sky))))
      (font-lock-function-name-face ((,class (:foreground ,link))))
      (font-lock-keyword-face ((,class (:foreground ,soft :weight bold))))
      (font-lock-string-face ((,class (:foreground ,deep))))
      (font-lock-type-face ((,class (:foreground ,hero))))
      (font-lock-variable-name-face ((,class (:foreground ,ice))))
      (font-lock-warning-face ((,class (:foreground ,ice :weight bold))))
      (font-lock-negation-char-face ((,class (:foreground ,ice))))
      (font-lock-preprocessor-face ((,class (:foreground ,soft))))
      (font-lock-regexp-grouping-backslash ((,class (:foreground ,sky))))
      (font-lock-regexp-grouping-construct ((,class (:foreground ,sky))))

      ;; Tree-sitter (Emacs 29+)
      (font-lock-function-call-face ((,class (:foreground ,link))))
      (font-lock-property-name-face ((,class (:foreground ,ice))))
      (font-lock-property-use-face ((,class (:foreground ,ice))))
      (font-lock-number-face ((,class (:foreground ,sky))))
      (font-lock-operator-face ((,class (:foreground ,fg))))
      (font-lock-punctuation-face ((,class (:foreground ,fg-alt))))
      (font-lock-bracket-face ((,class (:foreground ,fg-alt))))
      (font-lock-delimiter-face ((,class (:foreground ,fg-alt))))
      (font-lock-escape-face ((,class (:foreground ,sky))))

      ;; Mode line
      (mode-line ((,class (:background ,bg-hl :foreground ,fg :box nil))))
      (mode-line-inactive ((,class (:background ,bg-alt :foreground ,fg-alt :box nil))))
      (mode-line-buffer-id ((,class (:foreground ,hero :weight bold))))
      (mode-line-emphasis ((,class (:foreground ,fg-light :weight bold))))
      (mode-line-highlight ((,class (:foreground ,hero))))
      (header-line ((,class (:background ,bg-alt :foreground ,fg))))

      ;; Search
      (isearch ((,class (:foreground ,bg :background ,hero :weight bold))))
      (isearch-fail ((,class (:foreground ,bg :background ,ice))))
      (lazy-highlight ((,class (:foreground ,fg-light :background ,bg-hl))))

      ;; Parens
      (show-paren-match ((,class (:background ,bg-hl :foreground ,hero :weight bold))))
      (show-paren-mismatch ((,class (:background ,ice :foreground ,bg :weight bold))))

      ;; Line numbers
      (line-number ((,class (:foreground ,comment :background ,bg))))
      (line-number-current-line ((,class (:foreground ,hero :background ,bg-alt :weight bold))))

      ;; Links
      (link ((,class (:foreground ,link :underline t))))
      (link-visited ((,class (:foreground ,soft :underline t))))
      (button ((,class (:foreground ,link :underline t))))

      ;; Compilation
      (compilation-error ((,class (:foreground ,ice))))
      (compilation-warning ((,class (:foreground ,sky))))
      (compilation-info ((,class (:foreground ,matrix))))

      ;; Completions
      (completions-common-part ((,class (:foreground ,hero))))
      (completions-first-difference ((,class (:foreground ,ice :weight bold))))
      (completions-annotations ((,class (:foreground ,fg-alt))))

      ;; Diffs
      (diff-added ((,class (:foreground ,deep :background ,bg))))
      (diff-removed ((,class (:foreground ,ice :background ,bg))))
      (diff-changed ((,class (:foreground ,sky :background ,bg))))
      (diff-header ((,class (:foreground ,soft :background ,bg-alt))))
      (diff-file-header ((,class (:foreground ,hero :background ,bg-alt :weight bold))))
      (diff-hunk-header ((,class (:foreground ,matrix :background ,bg-alt))))

      ;; Error/warning/success
      (error ((,class (:foreground ,ice :weight bold))))
      (warning ((,class (:foreground ,sky :weight bold))))
      (success ((,class (:foreground ,deep :weight bold))))

      ;; Pulse (for navigation highlighting)
      (pulse-highlight-face ((,class (:background ,bg-hl :extend t))))
      (pulse-highlight-start-face ((,class (:background ,bg-hl :extend t))))

      ;; Company
      (company-tooltip ((,class (:background ,bg-alt :foreground ,fg))))
      (company-tooltip-common ((,class (:foreground ,hero))))
      (company-tooltip-common-selection ((,class (:foreground ,hero :weight bold))))
      (company-tooltip-selection ((,class (:background ,bg-hl :foreground ,fg-light))))
      (company-tooltip-annotation ((,class (:foreground ,fg-alt))))
      (company-scrollbar-bg ((,class (:background ,bg-alt))))
      (company-scrollbar-fg ((,class (:background ,bg-hl))))
      (company-preview ((,class (:foreground ,fg-alt))))
      (company-preview-common ((,class (:foreground ,hero))))

      ;; Corfu
      (corfu-default ((,class (:background ,bg-alt :foreground ,fg))))
      (corfu-current ((,class (:background ,bg-hl :foreground ,fg-light))))
      (corfu-bar ((,class (:background ,bg-hl))))
      (corfu-border ((,class (:background ,bg-hl))))
      (corfu-annotations ((,class (:foreground ,fg-alt))))

      ;; Codeium
      (codeium-overlay-face ((,class (:foreground ,fg-alt :slant italic))))

      ;; gptel
      (gptel-context-face ((,class (:background ,bg-alt :extend t))))
      (gptel-prompt-face ((,class (:foreground ,hero :weight bold))))
      (gptel-response-face ((,class (:foreground ,fg))))

      ;; Vertico
      (vertico-current ((,class (:background ,bg-hl :foreground ,fg-light :extend t))))
      (vertico-group-title ((,class (:foreground ,hero :weight bold))))
      (vertico-group-separator ((,class (:foreground ,bg-hl :strike-through t))))

      ;; Orderless
      (orderless-match-face-0 ((,class (:foreground ,hero :weight bold))))
      (orderless-match-face-1 ((,class (:foreground ,link :weight bold))))
      (orderless-match-face-2 ((,class (:foreground ,soft :weight bold))))
      (orderless-match-face-3 ((,class (:foreground ,sky :weight bold))))

      ;; Marginalia
      (marginalia-documentation ((,class (:foreground ,fg-alt :slant italic))))
      (marginalia-key ((,class (:foreground ,soft))))
      (marginalia-mode ((,class (:foreground ,matrix))))
      (marginalia-date ((,class (:foreground ,sky))))
      (marginalia-size ((,class (:foreground ,sky))))

      ;; Consult
      (consult-preview-match ((,class (:background ,bg-hl))))
      (consult-preview-cursor ((,class (:background ,hero :foreground ,bg))))
      (consult-file ((,class (:foreground ,fg))))
      (consult-bookmark ((,class (:foreground ,link))))
      (consult-key ((,class (:foreground ,soft))))

      ;; Magit
      (magit-section-heading ((,class (:foreground ,hero :weight bold))))
      (magit-section-highlight ((,class (:background ,bg-alt :extend t))))
      (magit-branch-local ((,class (:foreground ,link))))
      (magit-branch-remote ((,class (:foreground ,deep))))
      (magit-branch-current ((,class (:foreground ,hero :weight bold :box t))))
      (magit-diff-added ((,class (:foreground ,deep :background ,bg))))
      (magit-diff-added-highlight ((,class (:foreground ,deep :background ,bg-alt))))
      (magit-diff-removed ((,class (:foreground ,ice :background ,bg))))
      (magit-diff-removed-highlight ((,class (:foreground ,ice :background ,bg-alt))))
      (magit-diff-context ((,class (:foreground ,fg-alt))))
      (magit-diff-context-highlight ((,class (:foreground ,fg-alt :background ,bg-alt))))
      (magit-diff-hunk-heading ((,class (:foreground ,fg :background ,bg-hl))))
      (magit-diff-hunk-heading-highlight ((,class (:foreground ,fg-light :background ,bg-hl))))
      (magit-diff-file-heading ((,class (:foreground ,fg :weight bold))))
      (magit-hash ((,class (:foreground ,fg-alt))))
      (magit-log-author ((,class (:foreground ,link))))
      (magit-log-date ((,class (:foreground ,fg-alt))))
      (magit-tag ((,class (:foreground ,sky))))
      (magit-dimmed ((,class (:foreground ,comment))))

      ;; Forge
      (forge-topic-open ((,class (:foreground ,deep))))
      (forge-topic-closed ((,class (:foreground ,fg-alt))))
      (forge-topic-merged ((,class (:foreground ,matrix))))

      ;; Diff-hl
      (diff-hl-insert ((,class (:foreground ,deep :background ,deep))))
      (diff-hl-delete ((,class (:foreground ,ice :background ,ice))))
      (diff-hl-change ((,class (:foreground ,sky :background ,sky))))

      ;; Git gutter
      (git-gutter:added ((,class (:foreground ,deep :weight bold))))
      (git-gutter:deleted ((,class (:foreground ,ice :weight bold))))
      (git-gutter:modified ((,class (:foreground ,sky :weight bold))))

      ;; Flycheck / Flymake
      (flycheck-error ((,class (:underline (:style wave :color ,ice)))))
      (flycheck-warning ((,class (:underline (:style wave :color ,sky)))))
      (flycheck-info ((,class (:underline (:style wave :color ,matrix)))))
      (flymake-error ((,class (:underline (:style wave :color ,ice)))))
      (flymake-warning ((,class (:underline (:style wave :color ,sky)))))
      (flymake-note ((,class (:underline (:style wave :color ,matrix)))))

      ;; LSP
      (lsp-face-highlight-read ((,class (:background ,bg-hl :underline t))))
      (lsp-face-highlight-write ((,class (:background ,bg-hl :underline t :weight bold))))
      (lsp-face-highlight-textual ((,class (:background ,bg-hl))))
      (lsp-ui-doc-background ((,class (:background ,bg-alt))))
      (lsp-ui-sideline-code-action ((,class (:foreground ,hero))))
      (lsp-headerline-breadcrumb-path-face ((,class (:foreground ,fg-alt))))
      (lsp-headerline-breadcrumb-symbols-face ((,class (:foreground ,link))))
      (lsp-headerline-breadcrumb-separator-face ((,class (:foreground ,fg-alt))))

      ;; Rainbow delimiters
      (rainbow-delimiters-depth-1-face ((,class (:foreground ,hero))))
      (rainbow-delimiters-depth-2-face ((,class (:foreground ,link))))
      (rainbow-delimiters-depth-3-face ((,class (:foreground ,soft))))
      (rainbow-delimiters-depth-4-face ((,class (:foreground ,sky))))
      (rainbow-delimiters-depth-5-face ((,class (:foreground ,deep))))
      (rainbow-delimiters-depth-6-face ((,class (:foreground ,matrix))))
      (rainbow-delimiters-depth-7-face ((,class (:foreground ,ice))))
      (rainbow-delimiters-depth-8-face ((,class (:foreground ,corp))))
      (rainbow-delimiters-depth-9-face ((,class (:foreground ,fg-alt))))
      (rainbow-delimiters-unmatched-face ((,class (:foreground ,ice :weight bold))))

      ;; Which-key
      (which-key-key-face ((,class (:foreground ,hero))))
      (which-key-command-description-face ((,class (:foreground ,fg))))
      (which-key-group-description-face ((,class (:foreground ,link))))
      (which-key-separator-face ((,class (:foreground ,comment))))

      ;; Dashboard
      (dashboard-banner-logo-title ((,class (:foreground ,hero :weight bold))))
      (dashboard-heading ((,class (:foreground ,link :weight bold))))
      (dashboard-items-face ((,class (:foreground ,fg))))
      (dashboard-navigator ((,class (:foreground ,soft))))
      (dashboard-footer-face ((,class (:foreground ,fg-alt :slant italic))))

      ;; Doom modeline
      (doom-modeline-bar ((,class (:background ,hero))))
      (doom-modeline-bar-inactive ((,class (:background ,bg-hl))))
      (doom-modeline-buffer-file ((,class (:foreground ,fg :weight bold))))
      (doom-modeline-buffer-modified ((,class (:foreground ,ice :weight bold))))
      (doom-modeline-buffer-path ((,class (:foreground ,fg-alt))))
      (doom-modeline-project-dir ((,class (:foreground ,link))))
      (doom-modeline-info ((,class (:foreground ,matrix))))
      (doom-modeline-warning ((,class (:foreground ,sky))))
      (doom-modeline-urgent ((,class (:foreground ,ice))))

      ;; Org mode
      (org-level-1 ((,class (:foreground ,hero   :weight bold :height 1.0))))
      (org-level-2 ((,class (:foreground ,link   :weight bold :height 1.0))))
      (org-level-3 ((,class (:foreground ,soft   :weight bold :height 1.0))))
      (org-level-4 ((,class (:foreground ,sky    :weight bold :height 1.0))))
      (org-level-5 ((,class (:foreground ,deep   :weight bold :height 1.0))))
      (org-level-6 ((,class (:foreground ,matrix :weight bold :height 1.0))))
      (org-level-7 ((,class (:foreground ,ice    :weight bold :height 1.0))))
      (org-level-8 ((,class (:foreground ,fg-alt :weight bold :height 1.0))))
      (org-document-title ((,class (:foreground ,hero :weight bold :height 1.4))))
      (org-document-info ((,class (:foreground ,fg-alt))))
      (org-document-info-keyword ((,class (:foreground ,comment))))
      (org-todo ((,class (:foreground ,ice :weight bold))))
      (org-done ((,class (:foreground ,deep :weight bold))))
      (org-headline-done ((,class (:foreground ,fg-alt))))
      (org-date ((,class (:foreground ,sky :underline t))))
      (org-link ((,class (:foreground ,link :underline t))))
      (org-tag ((,class (:foreground ,fg-alt :weight bold))))
      (org-block ((,class (:background ,bg-alt :extend t))))
      (org-block-begin-line ((,class (:foreground ,comment :background ,bg-alt :extend t))))
      (org-block-end-line ((,class (:foreground ,comment :background ,bg-alt :extend t))))
      (org-code ((,class (:foreground ,sky))))
      (org-verbatim ((,class (:foreground ,deep))))
      (org-table ((,class (:foreground ,fg))))
      (org-special-keyword ((,class (:foreground ,comment))))
      (org-meta-line ((,class (:foreground ,comment))))

      ;; Markdown mode
      (markdown-header-face-1 ((,class (:foreground ,hero   :weight bold :height 1.0))))
      (markdown-header-face-2 ((,class (:foreground ,link   :weight bold :height 1.0))))
      (markdown-header-face-3 ((,class (:foreground ,soft   :weight bold :height 1.0))))
      (markdown-header-face-4 ((,class (:foreground ,sky    :weight bold :height 1.0))))
      (markdown-header-face-5 ((,class (:foreground ,deep   :weight bold :height 1.0))))
      (markdown-header-face-6 ((,class (:foreground ,matrix :weight bold :height 1.0))))
      (markdown-code-face ((,class (:background ,bg-alt))))
      (markdown-inline-code-face ((,class (:foreground ,sky))))
      (markdown-link-face ((,class (:foreground ,link))))
      (markdown-url-face ((,class (:foreground ,fg-alt :underline t))))
      (markdown-bold-face ((,class (:foreground ,fg-light :weight bold))))
      (markdown-italic-face ((,class (:foreground ,fg :slant italic))))

      ;; Treemacs
      (treemacs-root-face ((,class (:foreground ,hero :weight bold :height 1.1))))
      (treemacs-directory-face ((,class (:foreground ,link))))
      (treemacs-file-face ((,class (:foreground ,fg))))
      (treemacs-git-modified-face ((,class (:foreground ,sky))))
      (treemacs-git-added-face ((,class (:foreground ,deep))))
      (treemacs-git-untracked-face ((,class (:foreground ,ice))))

      ;; Eshell
      (eshell-prompt ((,class (:foreground ,hero :weight bold))))
      (eshell-ls-directory ((,class (:foreground ,link :weight bold))))
      (eshell-ls-symlink ((,class (:foreground ,soft))))
      (eshell-ls-executable ((,class (:foreground ,deep :weight bold))))
      (eshell-ls-archive ((,class (:foreground ,sky))))
      (eshell-ls-backup ((,class (:foreground ,fg-alt))))
      (eshell-ls-clutter ((,class (:foreground ,comment))))
      (eshell-ls-missing ((,class (:foreground ,ice :weight bold))))

      ;; Rg
      (rg-match-face ((,class (:foreground ,hero :weight bold))))
      (rg-file-tag-face ((,class (:foreground ,link))))
      (rg-filename-face ((,class (:foreground ,link :weight bold))))
      (rg-line-number-face ((,class (:foreground ,fg-alt))))
      (rg-context-face ((,class (:foreground ,fg))))
      (rg-info-face ((,class (:foreground ,matrix))))
      (rg-warning-face ((,class (:foreground ,sky))))
      (rg-error-face ((,class (:foreground ,ice))))

      ;; Elfeed
      (elfeed-search-title-face ((,class (:foreground ,fg))))
      (elfeed-search-unread-title-face ((,class (:foreground ,fg-light :weight bold))))
      (elfeed-search-feed-face ((,class (:foreground ,link))))
      (elfeed-search-tag-face ((,class (:foreground ,soft))))
      (elfeed-search-date-face ((,class (:foreground ,fg-alt))))

      ;; ERC
      (erc-default-face ((,class (:foreground ,fg))))
      (erc-nick-default-face ((,class (:foreground ,link :weight bold))))
      (erc-my-nick-face ((,class (:foreground ,hero :weight bold))))
      (erc-current-nick-face ((,class (:foreground ,hero :weight bold))))
      (erc-notice-face ((,class (:foreground ,fg-alt))))
      (erc-input-face ((,class (:foreground ,fg-light))))
      (erc-timestamp-face ((,class (:foreground ,fg-alt))))
      (erc-prompt-face ((,class (:foreground ,hero :weight bold))))

      ;; Info
      (info-title-1 ((,class (:foreground ,hero :weight bold :height 1.3))))
      (info-title-2 ((,class (:foreground ,link :weight bold :height 1.2))))
      (info-title-3 ((,class (:foreground ,soft :weight bold :height 1.1))))
      (info-title-4 ((,class (:foreground ,sky :weight bold))))
      (info-menu-header ((,class (:foreground ,hero :weight bold))))
      (info-node ((,class (:foreground ,hero :weight bold))))
      (info-xref ((,class (:foreground ,link :underline t))))
      (info-xref-visited ((,class (:foreground ,soft :underline t))))

      ;; Help
      (help-key-binding ((,class (:foreground ,hero :background ,bg-alt :box (:line-width -1 :color ,bg-hl)))))

      ;; Gptel
      (gptel-prompt ((,class (:foreground ,hero :weight bold))))
      (gptel-response ((,class (:foreground ,fg))))

      ;; Avy
      (avy-lead-face ((,class (:background ,hero :foreground ,bg :weight bold))))
      (avy-lead-face-0 ((,class (:background ,link :foreground ,bg :weight bold))))
      (avy-lead-face-1 ((,class (:background ,soft :foreground ,bg :weight bold))))
      (avy-lead-face-2 ((,class (:background ,sky :foreground ,bg :weight bold))))

      ;; Transient
      (transient-heading ((,class (:foreground ,hero :weight bold))))
      (transient-key ((,class (:foreground ,soft :weight bold))))
      (transient-argument ((,class (:foreground ,deep :weight bold))))
      (transient-value ((,class (:foreground ,sky))))
      (transient-inactive-argument ((,class (:foreground ,fg-alt))))
      (transient-inactive-value ((,class (:foreground ,fg-alt))))

      ;; Tab bar
      (tab-bar ((,class (:background ,bg-alt :foreground ,fg))))
      (tab-bar-tab ((,class (:background ,bg :foreground ,hero :weight bold))))
      (tab-bar-tab-inactive ((,class (:background ,bg-alt :foreground ,fg-alt))))
      (tab-line ((,class (:background ,bg-alt :foreground ,fg))))
      (tab-line-tab ((,class (:background ,bg :foreground ,hero :weight bold))))
      (tab-line-tab-current ((,class (:background ,bg :foreground ,hero :weight bold))))
      (tab-line-tab-inactive ((,class (:background ,bg-alt :foreground ,fg-alt))))

      ;; Hl-todo
      (hl-todo ((,class (:foreground ,ice :weight bold))))

      ;; Lean4
      (lean4-info-title-face ((,class (:foreground ,hero :weight bold))))
      (lean4-goal-face ((,class (:foreground ,fg))))
      (lean4-error-face ((,class (:foreground ,ice :weight bold))))
      (lean4-warning-face ((,class (:foreground ,sky))))
      (lean4-info-face ((,class (:foreground ,matrix))))

      ;; Vterm ANSI colors - map to palette to prevent rogue reds/greens
      ;; Normal colors (0-7)
      (vterm-color-black ((,class (:foreground ,bg-alt :background ,bg-alt))))
      (vterm-color-red ((,class (:foreground ,ice :background ,ice))))
      (vterm-color-green ((,class (:foreground ,deep :background ,deep))))
      (vterm-color-yellow ((,class (:foreground ,sky :background ,sky))))
      (vterm-color-blue ((,class (:foreground ,link :background ,link))))
      (vterm-color-magenta ((,class (:foreground ,soft :background ,soft))))
      (vterm-color-cyan ((,class (:foreground ,matrix :background ,matrix))))
      (vterm-color-white ((,class (:foreground ,fg :background ,fg))))

      ;; Bright colors (8-15) - use lighter/more saturated variants
      (vterm-color-bright-black ((,class (:foreground ,comment :background ,comment))))
      (vterm-color-bright-red ((,class (:foreground ,ice :background ,ice))))
      (vterm-color-bright-green ((,class (:foreground ,deep :background ,deep))))
      (vterm-color-bright-yellow ((,class (:foreground ,hero :background ,hero))))
      (vterm-color-bright-blue ((,class (:foreground ,link :background ,link))))
      (vterm-color-bright-magenta ((,class (:foreground ,soft :background ,soft))))
      (vterm-color-bright-cyan ((,class (:foreground ,matrix :background ,matrix))))
      (vterm-color-bright-white ((,class (:foreground ,fg-light :background ,fg-light))))

      ;; ANSI colors - map to palette to prevent rogue reds/greens
      ;; Normal colors (0-7)
      (ansi-color-black ((,class (:foreground ,bg-alt :background ,bg-alt))))
      (ansi-color-red ((,class (:foreground ,ice :background ,ice))))
      (ansi-color-green ((,class (:foreground ,deep :background ,deep))))
      (ansi-color-yellow ((,class (:foreground ,sky :background ,sky))))
      (ansi-color-blue ((,class (:foreground ,link :background ,link))))
      (ansi-color-magenta ((,class (:foreground ,soft :background ,soft))))
      (ansi-color-cyan ((,class (:foreground ,matrix :background ,matrix))))
      (ansi-color-white ((,class (:foreground ,fg :background ,fg))))

      ;; Bright colors (8-15) - use lighter/more saturated variants
      (ansi-color-bright-black ((,class (:foreground ,comment :background ,comment))))
      (ansi-color-bright-red ((,class (:foreground ,ice :background ,ice))))
      (ansi-color-bright-green ((,class (:foreground ,deep :background ,deep))))
      (ansi-color-bright-yellow ((,class (:foreground ,hero :background ,hero))))
      (ansi-color-bright-blue ((,class (:foreground ,link :background ,link))))
      (ansi-color-bright-magenta ((,class (:foreground ,soft :background ,soft))))
      (ansi-color-bright-cyan ((,class (:foreground ,matrix :background ,matrix))))
      (ansi-color-bright-white ((,class (:foreground ,fg-light :background ,fg-light)))))
    ))

(defun hypermodern/apply-theme (theme-name)
  "Apply THEME-NAME from hypermodern palettes."
  (interactive

   (list (intern (completing-read "Theme: "
                                  (mapcar #'car hypermodern/palettes)
                                  nil t))))

  (let* ((palette (hypermodern/get-palette theme-name))
         (faces (hypermodern/generate-faces palette)))
    (mapc #'disable-theme custom-enabled-themes)
    (dolist (face-spec faces)
      (let ((face (car face-spec))
            (spec (cadr face-spec)))
        (face-spec-set face spec 'face-defface-spec)))

    (setq hypermodern/current-theme theme-name)

    (let ((bg (plist-get palette :base00)))
      (modify-all-frames-parameters `((background-color . ,bg))))

    (message "Applied theme: %s" (plist-get palette :name))))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                               // css // reset
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defun hypermodern/css-reset ()
  "Strip typography crimes. Color only."

  ;; Nuclear option: redefine base italic/bold faces so inheritance doesn't override
  (set-face-attribute 'italic nil :slant 'normal :underline nil :weight 'normal)
  (set-face-attribute 'bold nil :weight 'normal)
  (set-face-attribute 'bold-italic nil :weight 'normal :slant 'normal)

  ;; Also reset specific font-lock faces (belt-and-suspenders)
  (dolist (face '(font-lock-comment-face font-lock-doc-face
                                         font-lock-keyword-face font-lock-builtin-face
                                         font-lock-function-name-face font-lock-type-face
                                         font-lock-warning-face))
    (when (facep face)
      (set-face-attribute face nil :weight 'normal :slant 'normal)))

  ;; BANISH SQUIGGLY UNDERLINES - remove all underlines from diagnostic faces
  (dolist (face '(flymake-error flymake-warning flymake-note
                                flycheck-error flycheck-warning flycheck-info
                                lsp-face-highlight-read lsp-face-highlight-write
                                lsp-face-highlight-textual))
    (when (facep face)
      (set-face-attribute face nil :underline nil)))

  (setq lsp-lens-enable nil
        lsp-diagnostics-attributes '())

  (setq lsp-ui-sideline-show-diagnostics nil
        lsp-ui-sideline-show-code-actions nil)
  )

;; Also remove underlines when diagnostic modes load
(with-eval-after-load 'flymake
  (dolist (face '(flymake-error flymake-warning flymake-note))
    (when (facep face)
      (set-face-attribute face nil :underline nil))))

(with-eval-after-load 'flycheck
  (dolist (face '(flycheck-error flycheck-warning flycheck-info))
    (when (facep face)
      (set-face-attribute face nil :underline nil))))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // hypermodern // ui system
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defvar hypermodern/ui-density 'tight)
(defvar hypermodern/ui-signal 'minimal)
(defvar hypermodern/ui-glow-level 'subtle)
(defvar hypermodern/ui-glow-halo 'auto)
(defvar hypermodern/ui-enable-pulse t)

(defvar hypermodern/ui-pulse-commands
  '(other-window windmove-left windmove-right windmove-up windmove-down
                 xref-find-definitions xref-find-references xref-go-back imenu goto-line
                 consult-line consult-ripgrep consult-buffer consult-imenu consult-goto-line
                 beginning-of-buffer end-of-buffer))

(defvar hypermodern/ui-cursor-style nil)
(defvar hypermodern/ui-font-preset 'auto)
(defvar hypermodern/ui-font-size 140)
(defvar hypermodern/ui-variable-font-size 150)
(defvar hypermodern/ui-padding nil)

(defvar hypermodern/ui-alpha 100)
(defvar hypermodern/ui-enable-transparency t)
(defvar hypermodern/ui-enable-ligatures nil)
(defvar hypermodern/ui-enable-dim t)

(defconst hypermodern/ui--font-presets
  '((auto :mono ("Berkeley Mono" "Iosevka Term" "Iosevka Fixed" "JetBrains Mono"
                 "Fira Code" "SF Mono" "Monaco" "DejaVu Sans Mono")
          :variable ("Berkeley Mono" "Iosevka Aile" "Inter" "SF Pro Text" "Noto Sans"))
    (berkeley :mono ("Berkeley Mono") :variable ("Berkeley Mono" "Inter" "Noto Sans"))
    (iosevka :mono ("Iosevka Term" "Iosevka Fixed" "Iosevka") :variable ("Iosevka Aile" "Inter"))
    (jetbrains :mono ("JetBrains Mono") :variable ("Inter" "Noto Sans"))
    (system :mono nil :variable nil)))

(defconst hypermodern/ui--style-presets
  '((:name "Minimal / Razorgirl" :theme ono-sendai-razorgirl :density tight :signal minimal :glow off :pulse nil)
    (:name "Minimal / Razorgirl / Glow" :theme ono-sendai-razorgirl :density tight :signal minimal :glow subtle :pulse t)
    (:name "Neon / Razorgirl" :theme ono-sendai-razorgirl :density tight :signal loud :trans t :glow neon :pulse t :dim t)
    (:name "GitHub / Robust" :theme ono-sendai-github :density tight :signal minimal :glow subtle :pulse t)
    (:name "Sprawl / Comfy" :theme ono-sendai-sprawl :density comfy :signal minimal :glow subtle :pulse t)
    (:name "Memphis / OLED" :theme ono-sendai-memphis :density tight :signal minimal :trans t :glow subtle :pulse t)
    (:name "Light / Neoform" :theme maas-neoform :density tight :signal minimal :glow subtle :pulse t)
    (:name "Light / Tessier" :theme maas-tessier :density tight :signal minimal :glow subtle :pulse t)))

(defun hypermodern/ui--font-installed-p (font)
  (and (stringp font) (member font (font-family-list))))

(defun hypermodern/ui--first-font (fonts)
  (when (listp fonts) (seq-find #'hypermodern/ui--font-installed-p fonts)))

(defun hypermodern/ui--color-blend (c1 c2 alpha)
  (when (and (stringp c1) (stringp c2))
    (require 'color)
    (let ((r1 (color-name-to-rgb c1))
          (r2 (color-name-to-rgb c2)))
      (when (and r1 r2)
        (apply #'color-rgb-to-hex
               (cl-mapcar (lambda (a b) (+ (* alpha a) (* (- 1 alpha) b))) r1 r2))))))

(defun hypermodern/ui--set-frame-param (key val)
  (set-frame-parameter nil key val)
  (setq default-frame-alist (assq-delete-all key default-frame-alist))
  (add-to-list 'default-frame-alist (cons key val)))

(defun hypermodern/ui--accent-color ()
  (let ((palette (hypermodern/get-palette hypermodern/current-theme)))
    (or (plist-get palette :base0A) "#54aeff")))

(defun hypermodern/ui--glow-alpha ()
  (pcase hypermodern/ui-glow-level ('off 0.0) ('subtle 0.08) ('neon 0.16) (_ 0.0)))

(defun hypermodern/ui--apply-fonts ()
  (let* ((preset (assq hypermodern/ui-font-preset hypermodern/ui--font-presets))
         (mono-list (plist-get (cdr preset) :mono))
         (var-list (plist-get (cdr preset) :variable))
         (mono (hypermodern/ui--first-font mono-list))
         (var (or (hypermodern/ui--first-font var-list) mono)))
    (when mono
      (set-face-attribute 'default nil :family mono :height hypermodern/ui-font-size)
      (set-face-attribute 'fixed-pitch nil :family mono :height hypermodern/ui-font-size))
    (when var
      (set-face-attribute 'variable-pitch nil :family var :height hypermodern/ui-variable-font-size))))

(defun hypermodern/ui--density-values (density)
  (pcase density
    ('tight  (list :pad 0  :fringe '(8 . 8)   :line-spacing 0))
    ('normal (list :pad 10 :fringe '(10 . 10) :line-spacing 0))
    ('comfy  (list :pad 16 :fringe '(12 . 12) :line-spacing 2))
    ('cinema (list :pad 28 :fringe '(14 . 14) :line-spacing 4))
    (_       (list :pad 0  :fringe '(8 . 8)   :line-spacing 0))))

(defun hypermodern/ui--apply-density ()
  (let* ((vals (hypermodern/ui--density-values hypermodern/ui-density))
         (pad (or hypermodern/ui-padding (plist-get vals :pad)))
         (fr (plist-get vals :fringe))
         (ls (plist-get vals :line-spacing)))
    (fringe-mode fr)
    (setq-default line-spacing ls)
    (hypermodern/ui--set-frame-param 'internal-border-width pad)))

(defun hypermodern/ui--apply-transparency ()
  (when (and hypermodern/ui-enable-transparency (display-graphic-p))
    (ignore-errors (hypermodern/ui--set-frame-param 'alpha-background hypermodern/ui-alpha))
    (ignore-errors (hypermodern/ui--set-frame-param 'alpha (cons hypermodern/ui-alpha hypermodern/ui-alpha)))))

(defun hypermodern/ui--apply-modeline ()
  (when (featurep 'doom-modeline)
    (setq doom-modeline-height (pcase hypermodern/ui-density ('tight 18) ('normal 20) ('comfy 22) ('cinema 26) (_ 20)))
    (pcase hypermodern/ui-signal
      ('minimal (setq doom-modeline-icon nil doom-modeline-major-mode-icon nil doom-modeline-minor-modes nil
                      doom-modeline-buffer-encoding nil doom-modeline-checker-simple-format t doom-modeline-modal nil))
      ('normal (setq doom-modeline-icon (display-graphic-p) doom-modeline-major-mode-icon (display-graphic-p)
                     doom-modeline-minor-modes nil doom-modeline-buffer-encoding nil doom-modeline-checker-simple-format t))
      ('loud (setq doom-modeline-icon (display-graphic-p) doom-modeline-major-mode-icon (display-graphic-p)
                   doom-modeline-minor-modes t doom-modeline-buffer-encoding t doom-modeline-checker-simple-format nil doom-modeline-modal t)))
    (doom-modeline-mode 1) (force-mode-line-update t)))

(defun hypermodern/ui--apply-glow ()

  (let* ((palette (hypermodern/get-palette hypermodern/current-theme))
         (bg (or (plist-get palette :base00) "#000000"))
         (accent (hypermodern/ui--accent-color))
         (a (hypermodern/ui--glow-alpha))
         (halo (and (> a 0.0) (hypermodern/ui--color-blend accent bg a)))
         (cursor (pcase hypermodern/ui-glow-level
                   ('off nil)
                   ('subtle (hypermodern/ui--color-blend accent bg 0.85))
                   ('neon accent)
                   (_ nil))))

    (when (and (display-graphic-p) halo)
      (when (facep 'internal-border) (set-face-background 'internal-border halo))
      (when (facep 'fringe) (set-face-background 'fringe (hypermodern/ui--color-blend halo bg 0.55))))

    (when cursor
      (ignore-errors (set-face-background 'cursor cursor) (set-cursor-color cursor))))
  )

;; pulse system
(defvar hypermodern/ui--pulse-hook-installed nil)

(defun hypermodern/ui--pulse-post-command ()
  (when (and hypermodern/ui-enable-pulse (memq this-command hypermodern/ui-pulse-commands))
    (when (require 'pulse nil 'noerror)
      (let* ((palette (hypermodern/get-palette hypermodern/current-theme))
             (bg (plist-get palette :base00))
             (accent (hypermodern/ui--accent-color))
             (pulse-color (hypermodern/ui--color-blend accent bg 0.15)))

        (when pulse-color
          (let ((pulse-iterations 8)
                (pulse-delay 0.04))
            (set-face-background 'pulse-highlight-face pulse-color)
            (pulse-momentary-highlight-one-line (point) 'pulse-highlight-face)))))))

(defun hypermodern/ui--pulse-enable ()
  (unless hypermodern/ui--pulse-hook-installed
    (add-hook 'post-command-hook #'hypermodern/ui--pulse-post-command)
    (setq hypermodern/ui--pulse-hook-installed t)))

(defun hypermodern/ui--pulse-disable ()
  (when hypermodern/ui--pulse-hook-installed
    (remove-hook 'post-command-hook #'hypermodern/ui--pulse-post-command)
    (setq hypermodern/ui--pulse-hook-installed nil)))


(defun hypermodern/reinit-vertical-divider (&optional _sync-with-mode-line)
  "Modern, non-destructive dividers. GUI uses window-divider; TTY uses │."
  (interactive "P")

  ;; GUI: thin dividers using built-ins
  (when (display-graphic-p)
    (setq window-divider-default-right-width 1
          window-divider-default-bottom-width 1
          window-divider-default-places t)
    (window-divider-mode 1))

  ;; TTY: draw a Unicode vertical rule. Do NOT change fringes or modeline.
  (unless (display-graphic-p)
    (unless standard-display-table
      (setq standard-display-table (make-display-table)))
    (set-display-table-slot
     standard-display-table 'vertical-border
     (make-glyph-code ?│))))

(defun hypermodern/ui-apply ()
  "Apply all UI settings."
  (interactive)

  (hypermodern/ui--apply-density)
  (hypermodern/ui--apply-fonts)
  (hypermodern/ui--apply-transparency)
  (hypermodern/ui--apply-modeline)
  (hypermodern/ui--apply-glow)

  (hypermodern/reinit-vertical-divider)

  (if hypermodern/ui-enable-pulse
      (hypermodern/ui--pulse-enable)
    (hypermodern/ui--pulse-disable))

  (when (and hypermodern/ui-enable-dim (require 'dimmer nil 'noerror))
    (setq dimmer-fraction 0.20) (dimmer-mode 1)))

(defun hypermodern/switch-dark ()
  (interactive)
  (hypermodern/apply-theme (intern (completing-read "Dark theme: " (hypermodern/dark-themes) nil t)))
  (hypermodern/ui-apply))

(defun hypermodern/switch-light ()
  (interactive)
  (hypermodern/apply-theme (intern (completing-read "Light theme: " (hypermodern/light-themes) nil t)))
  (hypermodern/ui-apply))

(defun hypermodern/toggle-dark-light ()
  (interactive)

  (if (eq 'dark (hypermodern/theme-variant hypermodern/current-theme))
      (hypermodern/apply-theme 'maas-neoform)
    (hypermodern/apply-theme 'ono-sendai-razorgirl))

  (hypermodern/ui-apply))

(defun hypermodern/cycle-theme ()
  (interactive)

  (let* ((all (mapcar #'car hypermodern/palettes))
         (pos (seq-position all hypermodern/current-theme))
         (next (mod (1+ (or pos -1)) (length all))))
    (hypermodern/apply-theme (nth next all))

    (hypermodern/ui-apply)))

(defun hypermodern/ui-style ()
  (interactive)

  (let* ((names (mapcar (lambda (p) (plist-get p :name)) hypermodern/ui--style-presets))
         (choice (completing-read "Style: " names nil t))
         (preset (seq-find (lambda (p) (string= (plist-get p :name) choice)) hypermodern/ui--style-presets)))

    (when preset
      (when (plist-member preset :theme) (hypermodern/apply-theme (plist-get preset :theme)))
      (when (plist-member preset :density) (setq hypermodern/ui-density (plist-get preset :density)))
      (when (plist-member preset :signal) (setq hypermodern/ui-signal (plist-get preset :signal)))
      (when (plist-member preset :glow) (setq hypermodern/ui-glow-level (plist-get preset :glow)))
      (when (plist-member preset :pulse) (setq hypermodern/ui-enable-pulse (plist-get preset :pulse)))
      (when (plist-member preset :dim) (setq hypermodern/ui-enable-dim (plist-get preset :dim)))
      (when (plist-member preset :trans) (setq hypermodern/ui-enable-transparency (plist-get preset :trans))))

    (hypermodern/ui-apply)))

(defun hypermodern/ui-toggle-glow ()
  (interactive)

  (setq hypermodern/ui-glow-level
        (pcase hypermodern/ui-glow-level ('off 'subtle) ('subtle 'neon) (_ 'off)))

  (hypermodern/ui-apply)

  (message "Glow: %s" hypermodern/ui-glow-level))

(defun hypermodern/ui-toggle-pulse ()
  (interactive)

  (setq hypermodern/ui-enable-pulse (not hypermodern/ui-enable-pulse))

  (hypermodern/ui-apply)

  (message "Pulse: %s" (if hypermodern/ui-enable-pulse "on" "off")))

(defun hypermodern/ui-menu ()
  (interactive)
  (call-interactively 'hypermodern/ui-style))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                            // disable // flymake // squiggles
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

;; Disable flymake globally
(with-eval-after-load 'flymake
  (remove-hook 'flymake-diagnostic-functions 'flymake-proc-legacy-flymake))

;; Prevent flymake from starting automatically
;; (setq flymake-start-on-flymake-mode nil)
;; (add-hook 'flymake-mode-hook (lambda () (flymake-mode -1)))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                // reinit // user // interface
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(setq inhibit-startup-screen t
      inhibit-startup-message t
      initial-scratch-message ""
      frame-title-format "// %b //"
      ring-bell-function 'ignore
      visible-bell nil
      use-dialog-box nil
      confirm-kill-processes nil
      echo-keystrokes 0.1
      scroll-conservatively 101
      scroll-margin 2
      scroll-preserve-screen-position t
      auto-save-default nil
      make-backup-files nil
      create-lockfiles nil
      backup-by-copying t
      require-final-newline t
      indent-tabs-mode nil
      cursor-in-non-selected-windows nil
      resize-mini-windows 'grow-only)

(setq-default
 indent-tabs-mode nil
 tab-width 2)

(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(blink-cursor-mode 1)
(column-number-mode 1)
(global-auto-revert-mode 1)
(global-hl-line-mode 1)
(show-paren-mode 1)
(fset 'yes-or-no-p 'y-or-n-p)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                        // frame // discipline
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

;; ── Shackle: No popup without permission ───────────────────────────

(use-package shackle
  :demand t

  :config
  (setq shackle-default-rule '(:select nil :inhibit-window-quit nil)
        shackle-default-size 0.3
        shackle-default-alignment 'below
        shackle-rules
        '(
          ;; ─ never show these automatically ─────────────────────────

          ("\\*Warnings\\*"                 :ignore t)
          ("\\*Async Shell Command\\*"      :ignore t)
          ("\\*Async-native-compile-log\\*" :ignore t)
          ("\\*Native-compile-Log\\*"       :ignore t)
          ("\\*straight-process\\*"         :ignore t)
          ("\\*flycheck errors\\*"          :ignore t)  ; use consult-flycheck
          ("\\*Flymake diagnostics.*"       :ignore t)
          ("\\*lsp-log\\*"                  :ignore t)
          ("\\*nixd.*"                      :ignore t)
          ("\\*tramp.*"                     :ignore t)
          ("\\*Deletions\\*"                :ignore t)
          ("\\*Quail Completions\\*"        :ignore t)

          ;; ─ bottom panel (no steal focus) ──────────────────────────

          (compilation-mode             :align below :size 0.25 :select nil :popup t)
          ("\\*compilation\\*"          :align below :size 0.25 :select nil :popup t)
          ("\\*Compile-Log\\*"          :align below :size 0.25 :select nil :popup t)
          ("\\*Messages\\*"             :align below :size 0.25 :select nil :popup t)
          ("\\*Backtrace\\*"            :align below :size 0.30 :select nil :popup t)
          ("\\*vc-diff\\*"              :align below :size 0.30 :select nil :popup t)
          ("\\*vc-change-log\\*"        :align below :size 0.30 :select nil :popup t)
          ("\\*Shell Command Output\\*" :align below :size 0.25 :select nil :popup t)
          ("\\*Pp Eval Output\\*"       :align below :size 0.25 :select nil :popup t)

          ;; ─ bottom panel (select) ──────────────────────────────────

          ("\\*rg\\*"                 :align below :size 0.4  :select t :popup t)
          ("\\*xref\\*"               :align below :size 0.3  :select t :popup t)
          ("\\*grep\\*"               :align below :size 0.4  :select t :popup t)
          ("\\*Occur\\*"              :align below :size 0.3  :select t :popup t)
          ("\\*eshell\\*"             :align below :size 0.3  :select t :popup t)
          (eshell-mode                :align below :size 0.3  :select t :popup t)
          (ghostel-mode               :align below :size 0.35 :select t :popup t)
          ("\\*ghostel.*"             :align below :size 0.35 :select t :popup t)
          (vterm-mode                 :align below :size 0.35 :select t :popup t)
          (term-mode                  :align below :size 0.35 :select t :popup t)

          ;; ─ right side (reference material) ────────────────────────

          (help-mode                  :align right :size 0.4  :select t   :popup t)
          (helpful-mode               :align right :size 0.4  :select t   :popup t)
          ("\\*Help\\*"               :align right :size 0.4  :select t   :popup t)
          ("\\*helpful.*"             :align right :size 0.4  :select t   :popup t)
          (Info-mode                  :align right :size 0.45 :select t   :popup t)
          ("\\*info\\*"               :align right :size 0.45 :select t   :popup t)
          ("\\*Man.*"                 :align right :size 0.4  :select t   :popup t)
          ("\\*eldoc\\*"              :align right :size 0.35 :select nil :popup t)
          ("\\*devdocs\\*"            :align right :size 0.45 :select t   :popup t)

          ;; ─ ai buffers ─────────────────────────────────────────────

          ("\\*gptel\\*"              :align right :size 0.45 :select t :popup t)
          ("\\*Claude\\*"             :align right :size 0.45 :select t :popup t)
          ("\\*ChatGPT\\*"            :align right :size 0.45 :select t :popup t)
          (gptel-mode                 :align right :size 0.45 :select t :popup t)
          ("\\*aider.*"               :align below :size 0.35 :select t :popup t)

          ;; ─ Magit (special handling) ───────────────────────────────
          (magit-status-mode          :same t :select t)
          (magit-log-mode             :same t :select t)
          (magit-diff-mode            :align below :size 0.5 :select nil :popup t)
          (magit-process-mode         :align below :size 0.2 :select nil :popup t)
          ("\\*magit-.*popup\\*"      :align below :size 0.35 :select t :popup t)
          ("COMMIT_EDITMSG"           :align below :size 0.4 :select t :popup t)

          ;; ─ lean4 ──────────────────────────────────────────────────

          ("\\*Lean 4.*"             :align right :size 0.35 :select nil :popup t)
          ("\\*Lean Goal\\*"         :align right :size 0.35 :select nil :popup t)
          ("\\*Lean Info\\*"         :align right :size 0.35 :select nil :popup t)

          ;; ─ Org/capture ────────────────────────────────────────────
          ("\\*Org Agenda\\*"         :align right :size 0.4 :select t :popup t)
          ("\\*Org Select\\*"         :align below :size 0.3 :select t :popup t)
          (org-capture-mode           :align below :size 0.35 :select t :popup t)

          ;; ─ Completion (never steal focus) ─────────────────────────
          ("\\*Completions\\*"        :align below :size 0.3 :select nil :popup t)
          ("\\*company-.*"            :ignore t)))
  (shackle-mode 1))

;; ── Dashboard protection ───────────────────────────────────────────

(defun hypermodern/protect-dashboard ()
  "Mark the dashboard window as dedicated so nothing can replace it."

  (when (and (boundp 'dashboard-buffer-name)
             (string= (buffer-name) dashboard-buffer-name))
    (set-window-dedicated-p (selected-window) t)))

(add-hook 'dashboard-after-initialize-hook #'hypermodern/protect-dashboard)

;; When something tries to use a dedicated window, pop a new one
(setq switch-to-buffer-in-dedicated-window 'pop)

;; Quick toggle for side windows (works with shackle's popups)
(defun hypermodern/toggle-side-windows ()
  "Toggle all side windows."
  (interactive)

  (if (window-with-parameter 'window-side)
      (window-toggle-side-windows)
    (message "No side windows to toggle")))

(global-set-key (kbd "C-c w s") #'hypermodern/toggle-side-windows)

;; ── Popper: Toggle popups with C-\ ─────────────────────────────────

(use-package popper
  :demand t
  :after shackle

  :bind (("C-\\"   . popper-toggle)       ; toggle last popup
         ("C-M-\\" . popper-cycle)        ; cycle through popups
         ("C-c \\" . popper-kill-latest)) ; kill popup

  :init
  (setq popper-reference-buffers
        '(;; By mode
          compilation-mode
          help-mode
          helpful-mode
          Info-mode
          ghostel-mode
          vterm-mode
          eshell-mode
          term-mode
          gptel-mode
          magit-process-mode
          magit-diff-mode
          ;; By name pattern
          "\\*Messages\\*"
          "\\*compilation\\*"
          "\\*Compile-Log\\*"
          "\\*Backtrace\\*"
          "\\*rg\\*"
          "\\*grep\\*"
          "\\*xref\\*"
          "\\*Occur\\*"
          "\\*Help\\*"
          "\\*helpful.*"
          "\\*info\\*"
          "\\*Man.*"
          "\\*gptel\\*"
          "\\*Claude\\*"
          "\\*aider.*"
          "\\*vc-.*"
          "\\*Shell Command Output\\*"
          "\\*Pp Eval Output\\*"
          "\\*Org Agenda\\*"
          "\\*Lean 4.*"
          "\\*Lean Goals\\*"
          "\\*Lean Info\\*"
          "COMMIT_EDITMSG"))

  :config
  (setq popper-display-control nil) ;; n.b. let shackle control placement...
  (popper-mode 1))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                               // window // movement
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defun hypermodern/hsplit ()
  (interactive)
  (split-window-right)
  (windmove-right))

(defun hypermodern/vsplit ()
  (interactive)
  (split-window-below)
  (windmove-down))

(defun hypermodern/rotate-windows ()
  (interactive)
  (let* ((windows (window-list))
         (buffers (mapcar #'window-buffer windows))
         (n (length windows)))
    (when (> n 1)
      (dotimes (i n)
        (set-window-buffer (nth i windows) (nth (mod (1+ i) n) buffers))))))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                     // mode // line
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package doom-modeline
  :demand t
  :hook (after-init . doom-modeline-mode)

  :config
  (setq doom-modeline-height 20
        doom-modeline-bar-width 3
        doom-modeline-icon nil
        doom-modeline-buffer-encoding nil))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                   // gptel // passage // openrouter
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defun hypermodern/gptel--netrc-get (host)
  "Get the password for HOST by parsing ~/.netrc DIRECTLY.

Deliberately bypasses `auth-source-search'. Two reasons it must:
  1. auth-source CACHES results for the session, so a rotated key in
     ~/.netrc (the agenix-decrypted file) is ignored until cache clear.
  2. We call `auth-source-pass-enable' later in this config, which inserts
     the passage store as an auth-source backend. After that,
     `auth-source-search :host \"openrouter.ai\"' can resolve against
     passage (returning a STALE/WRONG key) instead of the netrc file.
Both bugs manifested as gptel sending a wrong key and getting HTTP 401
\"Missing Authentication header\". Reading the file directly is
deterministic and always current."
  (let ((netrc (expand-file-name "~/.netrc")))
    (when (file-readable-p netrc)
      (with-temp-buffer
        (insert-file-contents netrc)
        (goto-char (point-min))
        ;; Find `machine HOST' then the next `password TOKEN' (login may sit
        ;; between them). Tolerates multi-line netrc stanzas.
        (when (re-search-forward
               (concat "machine[ \t]+" (regexp-quote host) "\\b") nil t)
          (when (re-search-forward "password[ \t]+\\([^ \t\n]+\\)" nil t)
            (match-string 1)))))))

(defvar hypermodern/gptel--current-key nil
  "Cached OpenRouter API key for this session.")

(defun hypermodern/gptel--passage-get (entry)
  "Get secret from passage store for ENTRY."

  (let ((result (string-trim
                 (shell-command-to-string
                  (format "passage show %s 2>/dev/null" entry)))))
    (unless (string-empty-p result) result)))

(defun hypermodern/gptel--passage-store-dir ()
  "Return the passage store directory from env or default."

  (or (getenv "PASSAGE_DIR")
      (expand-file-name "~/src/nixos-config/secrets/passage-store")))

(defun hypermodern/gptel--passage-insert (entry value)
  "Store VALUE in passage at ENTRY using rage directly.
Passage insert is broken when age isn't in PATH, so we use rage."

  (let* ((store-dir (hypermodern/gptel--passage-store-dir))
         (recipients-file (expand-file-name ".age-recipients" store-dir))
         (entry-file (expand-file-name (concat entry ".age") store-dir))
         (entry-dir (file-name-directory entry-file)))
    ;; Ensure directory exists
    (make-directory entry-dir t)
    ;; Encrypt with rage
    (with-temp-buffer
      (insert value)
      (if (zerop (call-process-region (point-min) (point-max) "rage"
                                      nil nil nil
                                      "-R" recipients-file
                                      "-o" entry-file))
          t
        (error "Failed to encrypt with rage")))))

(defun hypermodern/gptel-get-api-key ()
  "Get OpenRouter API key. Checks in order:
1. Session cache
2. netrc:openrouter.ai  (agenix-decrypted ~/.netrc; the source of truth)
3. passage:api/openrouter-emacs (only if you've provisioned one there)
4. OPENROUTER_API_KEY env var

netrc is tried BEFORE passage on purpose: the passage entry usually does
not exist (so `passage show` just spawns a failing subprocess and prints
an error), and the netrc key is the one that actually validates."

  (or hypermodern/gptel--current-key
      (setq hypermodern/gptel--current-key
            (or (hypermodern/gptel--netrc-get "openrouter.ai")
                (hypermodern/gptel--passage-get "api/openrouter-emacs")
                (getenv "OPENROUTER_API_KEY")))))

(defun hypermodern/gptel-refresh-key ()
  "Clear cached key, re-resolve, and rebuild the gptel backend's key.
The backend stores the key as a STRING (see the backend setup for why a
lambda there 401s), so a rotated key only takes effect once we both clear
the cache AND write the new string into `gptel-backend'."
  (interactive)
  (setq hypermodern/gptel--current-key nil)
  (let ((new-key (hypermodern/gptel-get-api-key)))
    (when (and new-key (bound-and-true-p gptel-backend))
      (setf (gptel-backend-key gptel-backend) new-key))
    (message "[gptel] Key %s" (if new-key "refreshed + applied to backend" "NOT found"))))

(defun hypermodern/gptel-provision-key ()
  "Provision a new OpenRouter API key and store in passage.
Uses the provisioning key from passage (api/openrouter-provisioning) or netrc."

  (interactive)

  (require 'url)
  (require 'json)

  (let* ((provisioning-key (or (hypermodern/gptel--passage-get "api/openrouter-provisioning")
                               (hypermodern/gptel--netrc-get "provisioning.openrouter.ai"))))
    (unless provisioning-key
      (user-error "No provisioning key found. Add to passage:api/openrouter-provisioning"))

    (message "Provisioning new OpenRouter key...")

    (let* ((url-request-method "POST")
           (url-request-extra-headers
            `(("Authorization" . ,(concat "Bearer " provisioning-key))
              ("Content-Type" . "application/json")))
           (url-request-data
            (json-encode `((name . ,(format "emacs-%s-%s"
                                            (system-name)
                                            (format-time-string "%Y%m%d"))))))
           (buffer (url-retrieve-synchronously "https://openrouter.ai/api/v1/keys" t t 30)))

      (if (not buffer)
          (user-error "Failed to connect to OpenRouter API")
        (unwind-protect
            (with-current-buffer buffer
              (goto-char (point-min))
              ;; Check HTTP status
              (unless (looking-at-p "HTTP/[0-9.]+ 2[0-9][0-9]")
                (user-error "OpenRouter API error: %s"
                            (buffer-substring (point) (line-end-position))))
              ;; Parse response
              (when (re-search-forward "\n\n" nil t)
                (let* ((json-object-type 'plist)
                       (response (json-read))
                       (new-key (plist-get response :key)))
                  (if (not new-key)
                      (user-error "No key in response: %s" response)
                    ;; Store in passage using rage directly
                    (hypermodern/gptel--passage-insert "api/openrouter-emacs" new-key)
                    (setq hypermodern/gptel--current-key new-key)
                    (message "New key provisioned and stored in passage:api/openrouter-emacs")))))
          (kill-buffer buffer))))))

;; ── Models organized by capability ─────────────────────────────────
(defvar hypermodern/gptel-models nil
  "Available models via OpenRouter. Populated dynamically on startup.")

(defvar hypermodern/gptel-models-cache-file
  (expand-file-name "gptel-models-cache.el" user-emacs-directory)
  "File to cache OpenRouter models list.")

(defvar hypermodern/gptel-models-cache-ttl 86400
  "Cache TTL in seconds (default 24 hours).")

;; BYOK providers that this key routes through (via GCP Vertex AI)
;; Determined by testing which model prefixes actually work with our key
;; Set to nil to show all models (for non-BYOK keys)
;; (defvar hypermodern/gptel-allowed-providers
;;   '("anthropic" "google" "deepseek" "meta-llama" "qwen" "moonshotai")

(defvar hypermodern/gptel-allowed-providers
  nil
  "List of provider prefixes that work with our BYOK key.
Models are filtered to only show those from these providers.
Set to nil to show all models.")

(defvar hypermodern/gptel-preferred-models
  '(anthropic/claude-sonnet-4.5    ; Fast + capable (default)
    anthropic/claude-sonnet-4.6
    anthropic/claude-opus-4.5      ; Most capable
    anthropic/claude-opus-4.6
    anthropic/claude-haiku-4.5     ; Fastest
    google/gemini-3.1-pro-preview
    deepseek/deepseek-chat)
  "Preferred models to try as default, in order of preference.")

(defvar hypermodern/gptel-provider-routing
  '()  ; Prefer Google Vertex for BYOK
  "Provider routing preferences for OpenRouter.
Passed as X-Provider-Routing header.")

(defun hypermodern/gptel-fetch-models ()
  "Fetch available models from OpenRouter API.
Filters to only models from `hypermodern/gptel-allowed-providers' if set."

  (require 'url)
  (require 'json)

  (let* ((api-key (hypermodern/gptel-get-api-key))
         (url-request-extra-headers
          `(("Authorization" . ,(concat "Bearer " api-key))))
         (buffer (url-retrieve-synchronously
                  "https://openrouter.ai/api/v1/models" t t 10)))
    (when buffer
      (unwind-protect
          (with-current-buffer buffer
            (goto-char (point-min))
            (when (re-search-forward "\n\n" nil t)
              (let* ((json-object-type 'alist)
                     (json-array-type 'list)
                     (response (json-read))
                     (all-models (alist-get 'data response))
                     (filtered-models
                      (if hypermodern/gptel-allowed-providers
                          (seq-filter
                           (lambda (m)
                             (let* ((id (alist-get 'id m))
                                    (provider (car (split-string id "/"))))
                               (member provider hypermodern/gptel-allowed-providers)))
                           all-models)
                        all-models)))
                (mapcar (lambda (m)
                          (let ((id (alist-get 'id m)))
                            (cons (hypermodern/gptel--model-display-name id)
                                  (intern id))))
                        filtered-models))))
        (kill-buffer buffer)))))

(defun hypermodern/gptel--model-display-name (model-id)
  "Convert MODEL-ID to a human-readable display name."

  (let* ((parts (split-string model-id "/"))
         (provider (car parts))
         (model (cadr parts)))
    (format "%s (%s)"
            (capitalize (replace-regexp-in-string "[-_]" " " (or model model-id)))
            provider)))

(defun hypermodern/gptel-load-models ()
  "Load models from cache or fetch from API."

  (let ((cache-valid (and (file-exists-p hypermodern/gptel-models-cache-file)
                          (< (float-time
                              (time-subtract
                               (current-time)
                               (file-attribute-modification-time
                                (file-attributes hypermodern/gptel-models-cache-file))))
                             hypermodern/gptel-models-cache-ttl))))
    (if cache-valid
        ;; Load from cache
        (with-temp-buffer
          (insert-file-contents hypermodern/gptel-models-cache-file)
          (setq hypermodern/gptel-models (read (current-buffer))))
      ;; Fetch fresh and cache
      (message "[gptel] Fetching available models from OpenRouter...")
      (let ((models (hypermodern/gptel-fetch-models)))
        (when models
          (setq hypermodern/gptel-models models)
          ;; Write cache
          (with-temp-file hypermodern/gptel-models-cache-file
            (prin1 models (current-buffer)))
          (message "[gptel] Loaded %d models" (length models))))))
  hypermodern/gptel-models)

(defun hypermodern/gptel-refresh-models ()
  "Force refresh models from OpenRouter API."
  (interactive)

  (when (file-exists-p hypermodern/gptel-models-cache-file)
    (delete-file hypermodern/gptel-models-cache-file))

  (hypermodern/gptel-load-models)
  ;; Update backend
  (when gptel-backend
    (setf (gptel-backend-models gptel-backend)
          (mapcar #'cdr hypermodern/gptel-models)))
  (message "[gptel] Refreshed %d models" (length hypermodern/gptel-models)))

;; ── System prompts library ─────────────────────────────────────────

(defvar hypermodern/gptel-prompts
  '(("Default" . nil)
    ("Concise" . "You are a helpful assistant. Be concise and direct. No preamble.")
    ("Coder" . "You are an expert programmer. Write clean, idiomatic code with minimal explanation. Prefer functional patterns. No markdown unless asked.")
    ("Code Review" . "You are a senior engineer doing code review. Be constructive but thorough. Point out bugs, suggest improvements, note good patterns.")
    ("Explain" . "You are a patient teacher. Explain concepts clearly with examples. Build up from fundamentals.")
    ("Emacs Lisp" . "You are an Emacs Lisp expert. Write idiomatic elisp. Use cl-lib, seq, and map functions. Prefer lexical binding.")
    ("Nix" . "You are a NixOS/Nix expert. Write idiomatic Nix expressions. Prefer flakes and modern patterns. Explain tradeoffs.")
    ("Haskell" . "You are a Haskell expert. Write idiomatic, type-safe code. Use appropriate abstractions (Functor, Monad, etc). Explain type signatures.")
    ("Rust" . "You are a Rust expert. Write idiomatic, safe Rust. Explain ownership/borrowing when relevant. Use iterators over loops.")
    ("Debug" . "Help me debug this issue. Ask clarifying questions. Think step by step. Consider edge cases.")
    ("Rewrite" . "Rewrite the following to be clearer and more concise. Preserve meaning. No explanation needed.")
    ("Summarize" . "Summarize the following concisely. Use bullet points for key takeaways."))
  "System prompt presets for different tasks.")

(use-package gptel
  :bind (("C-c g g" . gptel)
         ("C-c g s" . gptel-send)
         ("C-c g k" . gptel-abort)
         ("C-c g m" . gptel-menu)
         ("C-c g a" . hypermodern/gptel-switch-model)
         ("C-c g p" . hypermodern/gptel-switch-prompt)
         ("C-c g r" . hypermodern/gptel-rewrite-region)
         ("C-c g e" . hypermodern/gptel-explain-region)
         ("C-c g c" . hypermodern/gptel-code-region)
         ("C-c g b" . hypermodern/gptel-send-buffer)
         ("C-c g t" . hypermodern/gptel-toggle-tools)
         ("C-c g T" . hypermodern/gptel-agent-task)
         ("C-c g K" . hypermodern/gptel-refresh-key)
         ("C-c g M" . hypermodern/gptel-refresh-models)
         ("C-c g P" . hypermodern/gptel-provision-key))

  :hook (gptel-mode . visual-line-mode)

  :config
  ;; Get API key from netrc
  (let ((api-key (hypermodern/gptel-get-api-key)))
    (unless api-key
      (message "[gptel] No API key found. Add to netrc: machine openrouter.ai"))

    ;; Load available models (from cache or API)
    (hypermodern/gptel-load-models)

    ;; Configure OpenRouter backend with dynamically fetched models.
    ;;
    ;; CRITICAL: :key MUST be the eagerly-resolved STRING, not a lambda.
    ;; gptel re-invokes the :key function from inside its async curl
    ;; process/sentinel context, where our resolver's FIRST source
    ;; (`passage show ...` via shell-command-to-string) runs in a subprocess
    ;; that fails silently (no tty / different env), returns nil, and the
    ;; Authorization header is omitted -> "HTTP 401 Missing Authentication
    ;; header". Resolving once here and handing gptel a plain string sidesteps
    ;; the whole fragile re-resolution path. Use C-c g K to re-resolve and
    ;; rebuild the backend if the key rotates mid-session.
    (setq gptel-backend
          (gptel-make-openai "openrouter"
            :host "openrouter.ai"
            :endpoint "/api/v1/chat/completions"
            :stream t
            :key (or api-key "")
            :models (mapcar #'cdr hypermodern/gptel-models)))

    ;; Default to first available preferred model
    (setq gptel-model
          (or (seq-find (lambda (m) (member m (mapcar #'cdr hypermodern/gptel-models)))
                        hypermodern/gptel-preferred-models)
              (cdar hypermodern/gptel-models))))

  ;; Enable tool use by default
  (setq gptel-use-tools t)

  ;; Sensible defaults
  (setq gptel-default-mode 'org-mode
        gptel-display-buffer-action '(display-buffer-pop-up-window)
        gptel-prompt-prefix-alist '((org-mode . "* ")
                                    (markdown-mode . "## ")
                                    (text-mode . ""))
        gptel-response-prefix-alist '((org-mode . "** ")
                                      (markdown-mode . "### ")
                                      (text-mode . "\n")))

  ;; ── Interactive commands ───────────────────────────────────────────

  (defun hypermodern/gptel-switch-model ()
    "Switch gptel model with completion."
    (interactive)
    (let* ((choice (completing-read "Model: " (mapcar #'car hypermodern/gptel-models) nil t))
           (model (cdr (assoc choice hypermodern/gptel-models))))
      (setq gptel-model model)
      (message "Model: %s" choice)))

  (defun hypermodern/gptel-switch-prompt ()
    "Switch system prompt with completion."
    (interactive)
    (let* ((choice (completing-read "Prompt: " (mapcar #'car hypermodern/gptel-prompts) nil t))
           (prompt (cdr (assoc choice hypermodern/gptel-prompts))))
      (setq gptel--system-message prompt)
      (message "Prompt: %s" (if prompt choice "Default"))))

  (defun hypermodern/gptel-rewrite-region (start end)
    "Rewrite selected region to be clearer."
    (interactive "r")
    (let ((gptel--system-message "Rewrite the following to be clearer and more concise. Output only the rewritten text, no explanation."))
      (gptel-send start end)))

  (defun hypermodern/gptel-explain-region (start end)
    "Explain selected code/text."
    (interactive "r")
    (let ((gptel--system-message "Explain the following clearly and concisely."))
      (gptel-send start end)))

  (defun hypermodern/gptel-code-region (start end)
    "Generate/improve code for selected region."
    (interactive "r")
    (let ((gptel--system-message "You are an expert programmer. Write clean, idiomatic code. No markdown fences unless necessary."))
      (gptel-send start end)))

  (defun hypermodern/gptel-send-buffer ()
    "Send entire buffer to gptel."
    (interactive)

    (gptel-send (point-min) (point-max)))

  (defvar hypermodern/gptel-tools-enabled t
    "Whether gptel tools are enabled.")

  (defun hypermodern/gptel-toggle-tools ()
    "Toggle gptel tool use."
    (interactive)

    (setq hypermodern/gptel-tools-enabled (not hypermodern/gptel-tools-enabled))
    (setq gptel-use-tools hypermodern/gptel-tools-enabled)

    (message "Tools: %s" (if hypermodern/gptel-tools-enabled "enabled" "disabled")))

  ;; ── Tool definitions ───────────────────────────────────────────────

  ;; Register tools using gptel-make-tool API for agentic capabilities
  (setq gptel-tools
        (list

         ;; ── filesystem: read ─────────────────────────────────────────

         (gptel-make-tool
          :name "read_file"
          :function (lambda (filepath)
                      (let ((path (expand-file-name filepath)))
                        (if (file-exists-p path)
                            (with-temp-buffer
                              (insert-file-contents path)
                              (buffer-string))
                          (format "File not found: %s" path))))
          :description "Read and display the contents of a file"
          :args '((:name "filepath"
                         :type string
                         :description "Path to the file to read. Supports relative paths and ~."))
          :category "filesystem")

         ;; ── filesystem: list directory ───────────────────────────────

         (gptel-make-tool
          :name "list_directory"
          :function (lambda (directory)
                      (let ((path (expand-file-name directory)))
                        (if (file-directory-p path)
                            (mapconcat #'identity (directory-files path nil "^[^.]") "\n")
                          (format "Not a directory: %s" path))))
          :description "List the contents of a given directory"
          :args '((:name "directory"
                         :type string
                         :description "The path to the directory to list"))
          :category "filesystem")

         (gptel-make-tool
          :name "find_files"
          :function (lambda (directory pattern)
                      (shell-command-to-string
                       (format "fd -t f %s %s 2>/dev/null | head -100"
                               (shell-quote-argument pattern)
                               (shell-quote-argument (expand-file-name directory)))))
          :description "Find files matching a pattern recursively"
          :args '((:name "directory"
                         :type string
                         :description "The directory to search in")
                  (:name "pattern"
                         :type string
                         :description "The pattern to match (glob or regex)"))
          :category "filesystem")

         ;; ── filesystem: Write ────────────────────────────────────────

         (gptel-make-tool
          :name "create_file"
          :function (lambda (path filename content)
                      (let ((full-path (expand-file-name filename path)))
                        (with-temp-buffer
                          (insert content)
                          (write-file full-path))
                        (format "Created file %s" full-path)))
          :description "Create a new file with the specified content"
          :args '((:name "path"
                         :type string
                         :description "The directory where to create the file")
                  (:name "filename"
                         :type string
                         :description "The name of the file to create")
                  (:name "content"
                         :type string
                         :description "The content to write to the file"))
          :category "filesystem"
          :confirm t)

         (gptel-make-tool
          :name "edit_file"
          :function (lambda (filepath old_string new_string)
                      (let ((path (expand-file-name filepath)))
                        (if (not (file-exists-p path))
                            (format "File not found: %s" path)
                          (with-current-buffer (find-file-noselect path)
                            (let ((case-fold-search nil))
                              (goto-char (point-min))
                              (if (search-forward old_string nil t)
                                  (progn
                                    (replace-match new_string t t)
                                    (save-buffer)
                                    (format "Successfully edited %s" path))
                                (format "Could not find text to replace in %s" path)))))))
          :description "Edit a file by replacing old_string with new_string. The old_string must match exactly."
          :args '((:name "filepath"
                         :type string
                         :description "Path to the file to edit")
                  (:name "old_string"
                         :type string
                         :description "The exact text to find and replace")
                  (:name "new_string"
                         :type string
                         :description "The text to replace old_string with"))
          :category "filesystem"
          :confirm t)

         (gptel-make-tool
          :name "append_to_file"
          :function (lambda (filepath content)
                      (let ((path (expand-file-name filepath)))
                        (with-temp-buffer
                          (insert content)
                          (append-to-file (point-min) (point-max) path))
                        (format "Appended to %s" path)))
          :description "Append content to the end of a file"
          :args '((:name "filepath"
                         :type string
                         :description "Path to the file to append to")
                  (:name "content"
                         :type string
                         :description "The content to append"))
          :category "filesystem"
          :confirm t)

         ;; ── search ───────────────────────────────────────────────────

         (gptel-make-tool
          :name "grep_codebase"
          :function (lambda (pattern &optional directory file_pattern)
                      (let ((dir (or directory default-directory))
                            (glob (or file_pattern "*")))
                        (shell-command-to-string
                         (format "rg --no-heading -n --glob %s %s %s 2>/dev/null | head -100"
                                 (shell-quote-argument glob)
                                 (shell-quote-argument pattern)
                                 (shell-quote-argument (expand-file-name dir))))))
          :description "Search for a pattern in files using ripgrep"
          :args '((:name "pattern"
                         :type string
                         :description "The regex pattern to search for")
                  (:name "directory"
                         :type string
                         :description "Directory to search in (defaults to current)"
                         :optional t)
                  (:name "file_pattern"
                         :type string
                         :description "Glob pattern for files to search (e.g. *.py)"
                         :optional t))
          :category "search")

         ;; ── shell ────────────────────────────────────────────────────

         (gptel-make-tool
          :name "run_command"
          :function (lambda (command &optional working_dir)
                      (let ((default-directory (if (and working_dir (not (string= working_dir "")))
                                                   (expand-file-name working_dir)
                                                 default-directory)))
                        (shell-command-to-string command)))
          :description "Run a shell command and return output. Use for builds, tests, git, etc."
          :args '((:name "command"
                         :type string
                         :description "The shell command to execute")
                  (:name "working_dir"
                         :type string
                         :description "Directory to run command in (defaults to current)"
                         :optional t))
          :category "shell"
          :confirm t)

         ;; ── emacs/buffer ─────────────────────────────────────────────
         (gptel-make-tool
          :name "read_buffer"
          :function (lambda (buffer_name)
                      (if (buffer-live-p (get-buffer buffer_name))
                          (with-current-buffer buffer_name
                            (buffer-substring-no-properties (point-min) (point-max)))
                        (format "Buffer not found: %s" buffer_name)))
          :description "Read the contents of an open Emacs buffer"
          :args '((:name "buffer_name"
                         :type string
                         :description "The name of the buffer to read"))
          :category "emacs")

         (gptel-make-tool
          :name "list_buffers"
          :function (lambda ()
                      (mapconcat (lambda (b)
                                   (format "%s (%s)"
                                           (buffer-name b)
                                           (with-current-buffer b
                                             (symbol-name major-mode))))
                                 (buffer-list) "\n"))
          :description "List all open Emacs buffers with their major modes"
          :args '()
          :category "emacs")

         (gptel-make-tool
          :name "edit_buffer"
          :function (lambda (buffer_name old_string new_string)
                      (if (not (buffer-live-p (get-buffer buffer_name)))
                          (format "Buffer not found: %s" buffer_name)
                        (with-current-buffer buffer_name
                          (let ((case-fold-search nil))
                            (goto-char (point-min))
                            (if (search-forward old_string nil t)
                                (progn
                                  (replace-match new_string t t)
                                  (format "Successfully edited buffer %s" buffer_name))
                              (format "Could not find text in buffer %s" buffer_name))))))
          :description "Edit an open buffer by replacing old_string with new_string"
          :args '((:name "buffer_name"
                         :type string
                         :description "Name of the buffer to edit")
                  (:name "old_string"
                         :type string
                         :description "Text to find and replace")
                  (:name "new_string"
                         :type string
                         :description "Text to replace with"))
          :category "emacs"
          :confirm t)

         ;; ── git ──────────────────────────────────────────────────────

         (gptel-make-tool
          :name "git_status"
          :function (lambda (&optional directory)
                      (let ((default-directory (or directory default-directory)))
                        (shell-command-to-string "git status --short")))
          :description "Get git status for the repository"
          :args '((:name "directory"
                         :type string
                         :description "Repository directory (defaults to current)"
                         :optional t))
          :category "git")

         (gptel-make-tool
          :name "git_diff"
          :function (lambda (&optional file directory)
                      (let ((default-directory (or directory default-directory)))
                        (if file
                            (shell-command-to-string (format "git diff -- %s" (shell-quote-argument file)))
                          (shell-command-to-string "git diff"))))
          :description "Get git diff for changes"
          :args '((:name "file"
                         :type string
                         :description "Specific file to diff (optional)"
                         :optional t)
                  (:name "directory"
                         :type string
                         :description "Repository directory (defaults to current)"
                         :optional t))
          :category "git")

         (gptel-make-tool
          :name "git_log"
          :function (lambda (&optional count directory)
                      (let ((default-directory (or directory default-directory))
                            (n (or count 10)))
                        (shell-command-to-string
                         (format "git log --oneline -n %d" n))))
          :description "Get recent git commits"
          :args '((:name "count"
                         :type integer
                         :description "Number of commits to show (default 10)"
                         :optional t)
                  (:name "directory"
                         :type string
                         :description "Repository directory (defaults to current)"
                         :optional t))
          :category "git")))

  ;; ── Streaming polish ───────────────────────────────────────────────

  ;; Visual indicator while streaming
  (defvar hypermodern/gptel--spinner-frames '("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏"))
  (defvar hypermodern/gptel--spinner-index 0)
  (defvar hypermodern/gptel--spinner-timer nil)

  (defun hypermodern/gptel--spinner-start ()
    "Start spinner in mode line during streaming."
    (setq hypermodern/gptel--spinner-index 0)
    (setq hypermodern/gptel--spinner-timer
          (run-with-timer 0 0.1
                          (lambda ()
                            (setq hypermodern/gptel--spinner-index
                                  (mod (1+ hypermodern/gptel--spinner-index)
                                       (length hypermodern/gptel--spinner-frames)))
                            (force-mode-line-update t)))))

  (defun hypermodern/gptel--spinner-stop ()
    "Stop spinner."
    (when hypermodern/gptel--spinner-timer
      (cancel-timer hypermodern/gptel--spinner-timer)
      (setq hypermodern/gptel--spinner-timer nil)
      (force-mode-line-update t)))

  (defun hypermodern/gptel--spinner-string ()
    "Return current spinner frame or empty string."
    (if hypermodern/gptel--spinner-timer
        (concat " " (nth hypermodern/gptel--spinner-index hypermodern/gptel--spinner-frames) " ")
      ""))

  ;; Add spinner to mode line
  (defvar hypermodern/gptel--mode-line-construct
    '(:eval (hypermodern/gptel--spinner-string))
    "Mode-line construct for the gptel streaming spinner.")
  (unless (member hypermodern/gptel--mode-line-construct mode-line-misc-info)
    (push hypermodern/gptel--mode-line-construct mode-line-misc-info))

  ;; Hook into gptel's streaming lifecycle
  (defun hypermodern/gptel--before-send (&rest _)
    "Called before sending request."
    (hypermodern/gptel--spinner-start)
    (message "Sending to %s..." gptel-model))

  (defun hypermodern/gptel--after-response (beg end)
    "Called after response completes."
    (hypermodern/gptel--spinner-stop)
    (let ((tokens (- end beg)))
      (message "Response complete (%d chars)" tokens))
    ;; Pulse the response region briefly
    (when (and (fboundp 'pulse-momentary-highlight-region) (< (- end beg) 10000))
      (pulse-momentary-highlight-region beg end 'highlight)))

  (add-hook 'gptel-pre-request-hook #'hypermodern/gptel--before-send)
  (add-hook 'gptel-post-response-functions #'hypermodern/gptel--after-response)

  ;; ── Response formatting ────────────────────────────────────────────

  ;; Auto-wrap long lines in responses
  (defun hypermodern/gptel--format-response (beg end)
    "Format response region for readability."
    (save-excursion
      (goto-char beg)
      ;; Ensure code blocks are properly highlighted
      (when (derived-mode-p 'org-mode)
        (font-lock-ensure beg end))))

  (add-hook 'gptel-post-response-functions #'hypermodern/gptel--format-response)

  ;; ── Quick actions on responses ─────────────────────────────────────

  (defun hypermodern/gptel-copy-last-response ()
    "Copy the last gptel response to kill ring."
    (interactive)
    (save-excursion
      (let* ((prefix (or (alist-get major-mode gptel-response-prefix-alist) "** "))
             (prefix-re (regexp-quote (string-trim-right prefix))))
        (when (re-search-backward prefix-re nil t)
          (goto-char (match-end 0))
          (let ((beg (point)))
            (if (re-search-forward "^\\*+ " nil t)
                (kill-ring-save beg (match-beginning 0))
              (kill-ring-save beg (point-max)))
            (message "Response copied"))))))

  (defun hypermodern/gptel-yank-code-block ()
    "Extract and copy first code block from last response."
    (interactive)
    (save-excursion
      (when (re-search-backward "```" nil t 2)
        (forward-line 1)
        (let ((beg (point)))
          (re-search-forward "```" nil t)
          (forward-line 0)
          (kill-ring-save beg (point))
          (message "Code block copied")))))

  ;; ── Agentic mode ───────────────────────────────────────────────────
  ;; When enabled, auto-confirms safe tools and continues tool loops

  (defvar hypermodern/gptel-agent-mode nil
    "When non-nil, operate in agent mode with auto-confirmation of safe tools.")

  (defun hypermodern/gptel-toggle-agent-mode ()
    "Toggle agent mode for auto-confirming safe tool calls."
    (interactive)

    (setq hypermodern/gptel-agent-mode (not hypermodern/gptel-agent-mode))
    (if hypermodern/gptel-agent-mode
        (progn
          ;; In agent mode: auto-confirm read-only tools, prompt for writes
          (setq gptel-confirm-tool-calls 'confirm-dangerous)
          (message "Agent mode: ON (auto-confirm reads, prompt for writes)"))
      (progn
        ;; Normal mode: confirm all tool calls
        (setq gptel-confirm-tool-calls t)
        (message "Agent mode: OFF (confirm all tools)"))))

  (defun hypermodern/gptel-agent-task (task)
    "Start an agentic task. TASK is a description of what to accomplish.
Opens a new gptel buffer with agent mode enabled and tools available."
    (interactive "sTask: ")
    (let ((buf (gptel (format "*gptel-agent: %s*" (truncate-string-to-width task 30)))))
      (with-current-buffer buf
        (setq-local hypermodern/gptel-agent-mode t)
        (setq-local gptel-confirm-tool-calls 'confirm-dangerous)
        (setq-local gptel--system-message
                    "You are an expert software engineer with access to tools.
Use tools to explore the codebase, make edits, and run commands.
Work step by step. After each tool call, analyze the result and decide the next action.
When you've completed the task or need clarification, say so clearly.")
        (insert task)
        (gptel-send))))

  :bind (:map gptel-mode-map
              ("C-c g y" . hypermodern/gptel-copy-last-response)
              ("C-c g Y" . hypermodern/gptel-yank-code-block)
              ("C-c g A" . hypermodern/gptel-toggle-agent-mode)
              ("C-c g T" . hypermodern/gptel-agent-task)))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // aider - AI pair programming
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

;; (use-package aider
;;   :straight '(:host github :repo "tninja/aider.el")
;;   :config
;;   ;; Get OpenRouter key from netrc
;;   (defun hypermodern/aider-get-api-key ()
;;     "Get OpenRouter API key for aider from netrc."
;;     (require 'auth-source)
;;     (when-let ((found (car (auth-source-search :host "fuck.yuou.openrouter.ai" :max 1))))
;;       (let ((secret (plist-get found :secret)))
;;         (if (functionp secret) (funcall secret) secret))))

;;   ;; Configure aider to use OpenRouter
;;   (setq aider-args
;;         '("--openrouter"
;;           "--model" "openrouter/anthropic/claude-sonnet-4"
;;           "--dark-mode"
;;           "--auto-commits"
;;           "--stream"))

;;   ;; Set the API key in process environment
;;   (setq aider-process-environment
;;         `(,(concat "OPENROUTER_API_KEY=" (or (hypermodern/aider-get-api-key) ""))))

;;   ;; Keybindings
;;   :bind (("C-c i i" . aider-transient-menu)
;;          ("C-c i a" . aider-add-current-file)
;;          ("C-c i r" . aider-region-mode)
;;          ("C-c i c" . aider-code-change)
;;          ("C-c i q" . aider-ask-question)
;;          ("C-c i f" . aider-fix-failing-test-under-cursor)
;;          ("C-c i u" . aider-undo-last-change)
;;          ("C-c i R" . aider-reset)))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // minibuffer // completion
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package vertico
  :demand t
  :config
  (vertico-mode 1)
  (setq vertico-count 15
        vertico-cycle t))

;; vertico-reverse is a separate extension
(use-package vertico-reverse
  :after vertico
  :demand t
  :config
  (vertico-reverse-mode 1))

(use-package orderless
  :demand t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :demand t
  :config (marginalia-mode 1))

(use-package consult
  :demand t
  :bind (("C-x b" . consult-buffer)
         ("C-x C-r" . consult-recent-file)  ; better than recentf-open-files
         ;; ("C-s" . consult-line)
         ("M-g g" . consult-goto-line)
         ("M-s r" . consult-ripgrep)
         ("M-s l" . consult-line)           ; search in buffer
         ("M-s L" . consult-line-multi)     ; search across buffers
         ("M-y" . consult-yank-pop)))

(use-package embark
  :bind ("C-." . embark-act))

(use-package embark-consult
  :after (embark consult))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                // history // memory
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

;; Save minibuffer history (M-x commands, search strings, etc.)
(use-package savehist
  :demand t
  :config
  (setq savehist-file (expand-file-name "savehist" user-emacs-directory)
        savehist-save-minibuffer-history t
        savehist-additional-variables '(kill-ring
                                        search-ring
                                        regexp-search-ring
                                        compile-command
                                        shell-command-history
                                        extended-command-history
                                        file-name-history
                                        read-expression-history
                                        command-history
                                        query-replace-history))
  (savehist-mode 1))

;; Enhanced recentf - remember recent files
(use-package recentf
  :demand t
  :config
  (setq recentf-max-saved-items 500
        recentf-max-menu-items 25
        recentf-auto-cleanup 'never  ; don't clean on mode start (slow)
        recentf-save-file (expand-file-name "recentf" user-emacs-directory)
        recentf-exclude '("/tmp/" "/ssh:" "/sudo:" "\\.git/" "COMMIT_EDITMSG"
                          "\\.elc$" "/nix/store/" "\\.cache/"))
  ;; Save recentf periodically (every 5 mins) and on quit
  (run-at-time nil (* 5 60) 'recentf-save-list)
  (recentf-mode 1))

;; Prescient - frequency + recency sorting for completions
(use-package prescient
  :demand t
  :config
  (setq prescient-save-file (expand-file-name "prescient-save.el" user-emacs-directory)
        prescient-sort-full-matches-first t
        prescient-history-length 1000)
  (prescient-persist-mode 1))

;; Vertico integration - sort candidates by frecency
(use-package vertico-prescient
  :after (vertico prescient)
  :demand t
  :config
  (setq vertico-prescient-enable-filtering nil  ; use orderless for filtering
        vertico-prescient-enable-sorting t)     ; use prescient for sorting
  (vertico-prescient-mode 1))

;; Company integration - sort completions by frecency
(use-package company-prescient
  :after (company prescient)
  :demand t
  :config
  (company-prescient-mode 1))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                          // company
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package company
  :demand t
  :hook (after-init . global-company-mode)
  :bind (("M-TAB" . company-complete-common-or-cycle)
         ("C-M-i" . company-complete-common-or-cycle)
         ("<M-tab>" . company-complete-common-or-cycle)
         ("C-c f" . hypermodern/company-files))
  :config
  (setq company-idle-delay 0.1
        company-minimum-prefix-length 1
        company-backends '(company-capf company-files company-dabbrev))

  ;; Force filename completion
  (defun hypermodern/company-files ()
    "Complete filenames using company-files backend."
    (interactive)
    (let ((company-backends '(company-files)))
      (company-complete))))

(use-package yasnippet
  :demand t
  :config (yas-global-mode 1))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // codeium - AI code completion (FIM)
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package codeium
  :straight '(:host github :repo "Exafunction/codeium.el")
  :defer t
  :commands (codeium-complete codeium-install codeium-diagnose)
  :init
  ;; Mode line indicator
  (setq codeium-mode-line-enable
        (lambda (api) (not (memq api '(CancelRequest Heartbeat AcceptCompletion)))))

  ;; Get codeium status
  (defun hypermodern/codeium-status ()
    "Show codeium connection status."
    (interactive)
    (require 'codeium)
    (codeium-diagnose))

  ;; Auto-install language server if missing
  (defun hypermodern/codeium-ensure-installed ()
    "Install codeium language server if not present."
    (interactive)
    (require 'codeium)
    (unless (file-exists-p (expand-file-name "~/.emacs.d/codeium/codeium_language_server"))
      (codeium-install)))

  ;; Setup keybindings after codeium loads
  (with-eval-after-load 'codeium
    (when (boundp 'codeium-completion-map)
      (define-key codeium-completion-map (kbd "TAB") #'codeium-completion-accept)
      (define-key codeium-completion-map (kbd "<tab>") #'codeium-completion-accept)
      (define-key codeium-completion-map (kbd "M-]") #'codeium-completion-next)
      (define-key codeium-completion-map (kbd "M-[") #'codeium-completion-prev)
      (define-key codeium-completion-map (kbd "C-g") #'codeium-completion-cancel))
    ;; Add mode line after load
    (add-to-list 'mode-line-format '(:eval (car-safe codeium-mode-line)) t))

  :bind
  ("C-c a c" . codeium-complete)           ; Trigger completion
  ("C-c a i" . hypermodern/codeium-ensure-installed)  ; Install/check
  ("C-c a s" . hypermodern/codeium-status))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // tree-sitter
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package treesit-auto
  :demand t
  :config
  (setq treesit-auto-install 'prompt)
  (global-treesit-auto-mode 1))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // LSP
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :init (setq lsp-keymap-prefix "C-c l")
  :config
  (setq lsp-idle-delay 0.5
        lsp-completion-provider :capf
        lsp-headerline-breadcrumb-enable t
        lsp-headerline-breadcrumb-enable-diagnostics nil
        lsp-diagnostics-provider :flymake
        lsp-enable-snippet nil
        lsp-enable-on-type-formatting nil
        lsp-enable-indentation nil
        lsp-log-io nil))

(use-package lsp-ui
  :after lsp-mode
  :config
  (setq lsp-ui-sideline-enable nil
        lsp-ui-doc-enable t
        lsp-ui-doc-show-with-cursor nil))

(with-eval-after-load 'lsp-mode
  ;; Alternatively, if the above doesn't work (depends on lsp-mode version):
  (add-to-list 'lsp-language-id-configuration '(lean4-mode . "lean4"))
  )

;; (with-eval-after-load 'lsp-mode
;;   (setq lsp-warn-no-matched-clients nil))

(with-eval-after-load 'lsp-mode
  ;; Suppress "Unknown request method: workspace/inlayHint/refresh"
  ;; lean4-server sends this; lsp-mode doesn't handle it. Harmless.
  (advice-add 'lsp-warn :around
              (lambda (orig &rest args)
                (unless (and (car args)
                             (string-match-p "Unknown request method" (car args)))
                  (apply orig args)))))

(with-eval-after-load 'lsp-mode
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection
                     (lambda ()
                       (let ((wrapper (getenv "NIXD_LSP_WRAPPER")))
                         (if (and wrapper (file-executable-p wrapper))
                             (list wrapper)
                           '("nixd")))))
    :major-modes '(nix-mode nix-ts-mode)
    :server-id 'nixd
    :priority 10)))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // language // configuration // registry
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defvar hypermodern/language-registry
  '((nix
     :mode nix-mode
     :extensions ("\\.nix\\'")
     :backend lsp
     :server nixd
     :formatter nixfmt
     :format-all-formatter nixfmt
     :linter nil
     :type-checker nil)

    (haskell
     :mode haskell-mode
     :extensions ("\\.hs\\'")
     :backend lsp
     :server haskell-language-server
     :formatter fourmolu
     :format-all-formatter fourmolu
     :linter hlint
     :type-checker ghc
     :extra-packages (lsp-haskell))

    (rust
     :mode rust-mode
     :extensions ("\\.rs\\'")
     :backend lsp
     :server rust-analyzer
     :formatter rustfmt
     :format-all-formatter rustfmt
     :linter clippy
     :type-checker rust-analyzer)

    (python
     :mode python-mode
     :extensions ("\\.py\\'")
     :backend lsp
     :server pyright
     :formatter ruff-format
     :format-all-formatter ruff
     :linter ruff-check
     :type-checker pyright
     :builtin t
     :notes "ruff does both formatting and linting; pyright for types")

    (c
     :mode c-mode
     :extensions ("\\.c\\'" "\\.h\\'")
     :backend lsp
     :server clangd
     :formatter clang-format
     :format-all-formatter clang-format
     :linter clang-tidy
     :type-checker clangd
     :builtin t)

    (cpp
     :mode c++-mode
     :extensions ("\\.cpp\\'" "\\.cc\\'" "\\.cxx\\'" "\\.hpp\\'" "\\.hh\\'" "\\.hxx\\'")
     :backend lsp
     :server clangd
     :formatter clang-format
     :format-all-formatter clang-format
     :linter clang-tidy
     :type-checker clangd
     :builtin t)

    (cuda
     :mode cuda-mode
     :extensions ("\\.cu\\'" "\\.cuh\\'")
     :backend lsp
     :server clangd
     :formatter clang-format
     :format-all-formatter clang-format
     :linter clang-tidy
     :type-checker clangd
     :notes "clangd supports CUDA with --cuda-gpu-arch flag")

    (typescript
     :mode typescript-ts-mode
     :extensions (("\\.ts\\'" . typescript-ts-mode)
                  ("\\.tsx\\'" . tsx-ts-mode))
     :backend lsp
     :server typescript-language-server
     :formatter prettier
     :format-all-formatter prettier
     :linter eslint
     :type-checker typescript-language-server
     :builtin t
     :extra-modes (tsx-ts-mode))

    (javascript
     :mode js-ts-mode
     :extensions (("\\.js\\'" . js-ts-mode)
                  ("\\.jsx\\'" . js-ts-mode))
     :backend lsp
     :server typescript-language-server
     :formatter prettier
     :format-all-formatter prettier
     :linter eslint
     :type-checker nil
     :builtin t)

    (json
     :mode json-ts-mode
     :extensions ("\\.json\\'")
     :backend lsp
     :server vscode-json-language-server
     :formatter prettier
     :format-all-formatter prettier
     :linter nil
     :type-checker nil
     :builtin t)

    (yaml
     :mode yaml-mode
     :extensions ("\\.ya?ml\\'")
     :backend lsp
     :server yaml-language-server
     :formatter prettier
     :format-all-formatter prettier
     :linter yamllint
     :type-checker nil)

    (bash
     :mode bash-ts-mode
     :extensions ("\\.sh\\'")
     :backend lsp
     :server bash-language-server
     :formatter shfmt
     :format-all-formatter shfmt
     :linter shellcheck
     :type-checker nil
     :builtin t
     :notes "bash-language-server integrates shellcheck")

    (purescript
     :mode purescript-mode
     :extensions ("\\.purs\\'")
     :backend lsp
     :server purescript-language-server
     :formatter purs-tidy
     :format-all-formatter purs-tidy
     :linter nil
     :type-checker purescript-language-server
     :notes "lsp-mode ships a built-in client (server-id pursls); purs/spago resolved from PATH")

    (lean4
     :mode lean4-mode
     :extensions ("\\.lean\\'")
     :backend nil              ;; n.b. ← was 'lsp, but lean4-mode has built-in LSP
     :server lean              ;; lean4-mode handles this internally
     :formatter nil
     :format-all-formatter nil
     :linter nil
     :type-checker lean
     :notes "lean4-mode has built-in LSP client; do NOT use lsp-mode")

    (bazel
     :mode bazel-mode
     :extensions (("\\.bazel\\'" . bazel-mode)
                  ("\\.bzl\\'" . bazel-mode)
                  ("\\.star\\'" . bazel-mode)
                  ("WORKSPACE\\'" . bazel-mode)
                  ("WORKSPACE\\.bazel\\'" . bazel-mode)
                  ("BUILD\\'" . bazel-mode)
                  ("BUCK\\'" . bazel-mode)
                  ("BUILD\\.bazel\\'" . bazel-mode)
                  ("\\.BUILD\\'" . bazel-mode))
     :backend nil
     :server nil
     :formatter buildifier
     :format-all-formatter buildifier
     :linter buildifier
     :type-checker nil
     :notes "buildifier does both formatting and linting"))
  "Registry of language configurations for hypermodern Emacs.

Each entry is (LANGUAGE-NAME . PLIST) where PLIST contains:
  :mode             - Primary major mode symbol
  :extensions       - File extension patterns (string or list of (pattern . mode))
  :backend          - 'lsp, 'eglot, or nil for no LSP
  :server           - LSP server identifier (symbol)
  :formatter        - Preferred formatter command (symbol)
  :format-all-formatter - format-all backend name (symbol)
  :linter           - Linter/static analysis tool (symbol or nil)
  :type-checker     - Type checker tool (symbol or nil)
  :builtin          - t if mode is built-in to Emacs (no package needed)
  :extra-packages   - List of additional packages to install
  :extra-modes      - Additional modes to hook (e.g., tsx-ts-mode for typescript)
  :extra-config     - Lambda to run for additional configuration
  :notes            - Additional notes about the configuration (string)")

(defun hypermodern/language-get (lang key)
  "Get KEY from LANG configuration in hypermodern/language-registry."
  (plist-get (cdr (assq lang hypermodern/language-registry)) key))

(defun hypermodern/language-modes ()
  "Return list of all configured language modes."
  (mapcar (lambda (entry) (plist-get (cdr entry) :mode))
          hypermodern/language-registry))

(defun hypermodern/languages-using-lsp ()
  "Return list of languages configured to use LSP."
  (seq-filter (lambda (entry)
                (eq 'lsp (plist-get (cdr entry) :backend)))
              hypermodern/language-registry))

(defun hypermodern/languages-using-eglot ()
  "Return list of languages configured to use Eglot."
  (seq-filter (lambda (entry)
                (eq 'eglot (plist-get (cdr entry) :backend)))
              hypermodern/language-registry))

(defun hypermodern/language-info ()
  "Show configuration for current language."
  (interactive)

  (let* ((mode major-mode)
         (entry (seq-find (lambda (e)
                            (let ((plist (cdr e)))
                              (or (eq mode (plist-get plist :mode))
                                  (member mode (plist-get plist :extra-modes)))))
                          hypermodern/language-registry)))
    (if entry
        (let* ((name (car entry))
               (config (cdr entry))
               (backend (plist-get config :backend))
               (server (plist-get config :server))
               (formatter (plist-get config :formatter))
               (linter (plist-get config :linter))
               (type-checker (plist-get config :type-checker)))

          (message "[%s] backend=%s server=%s fmt=%s lint=%s type=%s"
                   name
                   (or backend "—")
                   (or server "—")
                   (or formatter "—")
                   (or linter "—")
                   (or type-checker "—")))

      (message "No language configuration found for %s" mode))))

(defun hypermodern/show-language-registry ()
  "Display the language registry in a buffer."
  (interactive)

  (with-current-buffer (get-buffer-create "*Language Registry*")
    (let ((inhibit-read-only t))
      (erase-buffer)
      (insert "# Hypermodern Language Registry\n\n")
      (insert (format "%-10s %-18s %-7s %-20s %-14s %-14s %-14s\n"
                      "Language" "Mode" "Backend" "Server" "Formatter" "Linter" "Type Check"))
      (insert (make-string 105 ?─) "\n")
      (dolist (entry hypermodern/language-registry)
        (let* ((name (car entry))
               (config (cdr entry))
               (mode (plist-get config :mode))
               (backend (plist-get config :backend))
               (server (plist-get config :server))
               (formatter (plist-get config :formatter))
               (linter (plist-get config :linter))
               (type-checker (plist-get config :type-checker))
               (notes (plist-get config :notes)))
          (insert (format "%-10s %-18s %-7s %-20s %-14s %-14s %-14s\n"
                          name
                          mode
                          (or backend "—")
                          (or server "—")
                          (or formatter "—")
                          (or linter "—")
                          (or type-checker "—")))
          (when notes
            (insert (format "  └─ %s\n" notes)))))
      (insert "\n")
      (insert (format "Total: %d languages\n" (length hypermodern/language-registry)))
      (insert (format "LSP:   %d languages\n" (length (hypermodern/languages-using-lsp))))
      (insert (format "Eglot: %d languages\n" (length (hypermodern/languages-using-eglot))))
      (goto-char (point-min))
      (special-mode))

    (pop-to-buffer (current-buffer))))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                        // languages
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package nix-mode
  :mode "\\.nix\\'"
  :hook (nix-mode . lsp-deferred))

(use-package haskell-mode
  :mode "\\.hs\\'"
  :hook (haskell-mode . lsp-deferred))

(use-package lsp-haskell
  :after (haskell-mode lsp-mode))

(use-package rust-mode
  :mode "\\.rs\\'"
  :hook (rust-mode . lsp-deferred))

(use-package cuda-mode
  :mode (("\\.cu\\'" . cuda-mode)
         ("\\.cuh\\'" . cuda-mode))
  :hook (cuda-mode . lsp-deferred))

(use-package python-mode
  :mode "\\.py\\'"
  :hook (python-mode . lsp-deferred))

(use-package typescript-ts-mode
  :mode (("\\.ts\\'" . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode))
  :hook ((typescript-ts-mode . lsp-deferred)
         (tsx-ts-mode . lsp-deferred)))

(use-package purescript-mode
  :mode "\\.purs\\'"
  :hook ((purescript-mode . lsp-deferred)
         (purescript-mode . turn-on-purescript-indentation))
  :config
  ;; lsp-mode ships a built-in PureScript client (lsp-purescript, server-id
  ;; 'pursls) that shells out to `purescript-language-server` on PATH. Make
  ;; sure it's loaded so lsp-deferred finds the client.
  (with-eval-after-load 'lsp-mode
    (require 'lsp-purescript nil t)))

(use-package markdown-mode
  :mode (("\\.md\\'" . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  :init
  (setq markdown-command "pandoc"
        markdown-fontify-code-blocks-natively t
        markdown-asymmetric-header t))

(use-package dhall-mode
  :mode "\\.dhall\\'")

;; lean4-mode has its own LSP client built in. It does NOT use lsp-mode.
;; The workspace/inlayHint/refresh spam is lsp-mode trying to attach
;; to .lean buffers alongside lean4-mode's own LSP — two clients talking
;; to one server. Kill lsp-mode for lean buffers.

(use-package lean4-mode
  :commands lean4-mode
  :mode "\\.lean\\'"

  :hook (lean4-mode . (lambda ()
                        ;; Unicode input: \to → →, \lam → λ, \forall → ∀, etc.
                        (set-input-method "Lean")))

  :config
  ;; Info buffer toggle — the function name has changed across versions
  (let ((toggle-fn (or (and (fboundp 'lean4-toggle-info) 'lean4-toggle-info)
                       (and (fboundp 'lean4-info-toggle) 'lean4-info-toggle)
                       (and (fboundp 'lean4-info-buffer-toggle) 'lean4-info-buffer-toggle))))
    (when toggle-fn
      (define-key lean4-mode-map (kbd "C-c C-i") toggle-fn)
      (define-key lean4-mode-map (kbd "C-c i") toggle-fn))))

(use-package bazel
  :mode (("\\.bazel\\'" . bazel-mode)
         ("\\.bzl\\'" . bazel-mode)
         ("\\.star\\'" . bazel-mode)
         ("WORKSPACE\\'" . bazel-mode)
         ("WORKSPACE\\.bazel\\'" . bazel-mode)
         ("BUILD\\'" . bazel-mode)
         ("BUILD\\.bazel\\'" . bazel-mode)
         ("\\.BUILD\\'" . bazel-mode)))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                       // formatting
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defun hypermodern/format-buffer ()
  "Format buffer if in prog-mode and formatter is available."
  (interactive)

  (if (derived-mode-p 'prog-mode 'text-mode)
      (progn
        (require 'format-all)
        (condition-case err
            (format-all-buffer nil)
          (error (message "[hypermodern] formatter not available: %s" err))))

    (message "[hypermodern] M-z: not in a formattable buffer")))

(use-package format-all
  :commands (format-all-buffer format-all-mode)
  :hook (prog-mode . format-all-mode)
  :config
  (setq format-all-show-errors 'never)

  ;; format-all-formatters uses LANGUAGE NAMES (strings), not mode names
  ;; The format is: ("Language Name" . (formatter-symbol args...))
  (setq-default format-all-formatters
                '(("Bazel"        . (buildifier))
                  ("C"            . (clang-format))
                  ("C++"          . (clang-format))
                  ("C#"           . (clang-format))
                  ("CSS"          . (prettier))
                  ("Dhall"        . (dhall))
                  ("Emacs Lisp"   . (emacs-lisp))
                  ("F#"           . (fantomas))
                  ("Go"           . (gofmt))
                  ("Haskell"      . (fourmolu))
                  ("HTML"         . (prettier))
                  ("JavaScript"   . (prettier))
                  ("JSON"         . (prettier))
                  ("JSX"          . (prettier))
                  ("Markdown"     . (prettier))
                  ;; Match treefmt (modules/flake/fmt.nix): nixfmt, strict,
                  ;; width 100. NOT nixpkgs-fmt — that fights treefmt on save.
                  ("Nix"          . (nixfmt "--strict" "--width" "100"))
                  ("Protocol Buffer" . (clang-format))
                  ("PureScript"   . (purs-tidy))
                  ("Python"       . (ruff))
                  ("Rust"         . (rustfmt))
                  ("Shell"        . (shfmt "-i" "2"))
                  ("TOML"         . (taplo))
                  ("TSX"          . (prettier))
                  ("TypeScript"   . (prettier))
                  ("YAML"         . (prettier))
                  ("Zig"          . (zig)))))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // magit
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package magit
  :bind ("C-x g" . magit))

(use-package forge
  :after magit)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // terminals
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;
;; ghostel is the PRIMARY terminal (libghostty-vt: true color, kitty
;; keyboard+graphics, hyperlinks, shell integration). vterm and eat stay
;; loaded as fallbacks but ghostel owns the "open a terminal" keys and the
;; project-switcher entry. See mk-hypermodern-emacs.nix for why the native
;; module is already present in the store and never auto-downloads.

(use-package ghostel
  :commands (ghostel ghostel-project ghostel-project-list-buffers)
  ;; C-x m is ghostel's documented launcher key; C-c t t is our mnemonic.
  :bind (("C-x m" . ghostel)
         ("C-c t t" . ghostel)
         :map ghostel-semi-char-mode-map
         ;; keep window motion identical to the old vterm bindings
         ("M-N" . windmove-right)
         ("M-P" . windmove-left)
         ;; shell-history feel: forward C-p/C-n to the shell
         ("M-p" . (lambda () (interactive) (ghostel-send-key "p" "ctrl")))
         ("M-n" . (lambda () (interactive) (ghostel-send-key "n" "ctrl")))
         :map project-prefix-map
         ("t" . ghostel-project)
         ("T" . ghostel-project-list-buffers))
  :init
  ;; Belt-and-suspenders: the nixpkgs build vendors ghostel-module.so in the
  ;; package dir (which is where ghostel reads it from when
  ;; ghostel-module-directory is nil), so the module is always present. Pin
  ;; auto-install to nil so a hypothetical missing module FAILS LOUDLY instead
  ;; of trying to fetch a binary from GitHub into a read-only store path.
  (setq ghostel-module-auto-install nil)
  :config
  ;; project switcher (C-x p) gains a Ghostel entry
  (when (boundp 'project-switch-commands)
    (add-to-list 'project-switch-commands '(ghostel-project "Ghostel") t)
    (add-to-list 'project-switch-commands
                 '(ghostel-project-list-buffers "Ghostel buffers") t))
  ;; let `gst`/`e`/`dow` style shell helpers call back into Emacs
  (when (boundp 'ghostel-eval-cmds)
    (add-to-list 'ghostel-eval-cmds
                 '("magit-status-setup-buffer" magit-status-setup-buffer))
    (add-to-list 'ghostel-eval-cmds
                 '("dired-other-window" dired-other-window)))
  :hook (ghostel-mode . (lambda () (hl-line-mode -1))))

;; Run compile/eshell-visual commands through ghostel's VT engine too.
(use-package ghostel-compile
  :after ghostel
  :hook (after-init . ghostel-compile-global-mode))

(use-package ghostel-eshell
  :after (ghostel eshell)
  :hook (eshell-load . ghostel-eshell-visual-command-mode))

;; Fallback terminals (no longer bound to launcher keys).
(use-package vterm
  :commands vterm
  :config
  (setq vterm-environment '("COLORTERM=truecolor"))
  :hook (vterm-mode . (lambda ()
                        (hl-line-mode -1)
                        (define-key vterm-mode-map (kbd "M-N") #'windmove-right)
                        (define-key vterm-mode-map (kbd "M-P") #'windmove-left))))

(use-package eat
  :commands eat)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                           // passage // age-based // password store
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

;; Configure password-store to use passage (age instead of GPG)
(use-package password-store
  :demand t
  :config
  ;; Point to passage instead of pass
  (setq password-store-executable "passage")

  ;; Use passage's directory structure - read from repo, not ~/.passage
  (setq auth-source-pass-filename
        (or (getenv "PASSAGE_DIR")
            (expand-file-name "~/src/nixos-config/secrets/passage-store"))))

;; OTP support (works with passage via pass-otp)
(use-package password-store-otp
  :after password-store)

;; pass.el - nice UI for browsing the store
(use-package pass
  :after password-store
  :commands pass
  :config
  ;; pass.el's tree-walking helpers below use f.el; ensure it's loaded.
  (require 'f)
  ;; Override the file extension check for .age files
  (defun hypermodern/pass--tree (&optional subdir)
    "Return a tree of all entries in SUBDIR for passage (.age files)."
    (unless subdir (setq subdir ""))
    (let ((path (f-join (password-store-dir) subdir)))
      (if (f-directory? path)
          (unless (string= (f-filename subdir) ".git")
            (cons (f-filename path)
                  (delq nil
                        (mapcar 'hypermodern/pass--tree
                                (f-entries path)))))
        (when (and (equal (f-ext path) "age")
                   (not (backup-file-name-p path)))
          (password-store--file-to-entry path)))))

  ;; Patch pass--tree to use .age extension
  (advice-add 'pass--tree :override #'hypermodern/pass--tree)

  ;; Fix file-to-entry for .age
  (defun hypermodern/password-store--file-to-entry (file)
    "Return entry name corresponding to FILE (.age extension)."
    (file-name-sans-extension (file-relative-name file (password-store-dir))))

  (advice-add 'password-store--file-to-entry :override #'hypermodern/password-store--file-to-entry)

  ;; Fix entry-to-file for .age
  (defun hypermodern/password-store--entry-to-file (entry)
    "Return file name corresponding to ENTRY (.age extension)."
    (concat (expand-file-name entry (password-store-dir)) ".age"))

  (advice-add 'password-store--entry-to-file :override #'hypermodern/password-store--entry-to-file)

  ;; Auto-mode for viewing .age files in the store
  (add-to-list 'auto-mode-alist
               (cons (format "%s/.*\\.age\\'"
                             (expand-file-name (password-store-dir)))
                     'pass-view-mode)))

;; Enable auth-source-pass for seamless credential lookup
(use-package auth-source-pass
  :demand t
  :config
  (auth-source-pass-enable))

;; Keybindings for passage
(global-set-key (kbd "C-c p p") #'pass)
(global-set-key (kbd "C-c p c") #'password-store-copy)
(global-set-key (kbd "C-c p g") #'password-store-generate)
(global-set-key (kbd "C-c p i") #'password-store-insert)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // tramp // bulletproof sshx
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package tramp
  :config
  (setq tramp-default-method "sshx"
        tramp-use-ssh-controlmaster-options nil
        tramp-histfile-override t
        tramp-connection-timeout 30
        tramp-shell-prompt-pattern "\\(?:^\\|\r\\)[^]#$%>\n]*[#$%>] *"
        vc-ignore-dir-regexp (format "\\(%s\\)\\|\\(%s\\)"
                                     vc-ignore-dir-regexp
                                     tramp-file-name-regexp)
        tramp-backup-directory-alist backup-directory-alist
        tramp-auto-save-directory temporary-file-directory
        tramp-default-remote-shell "/bin/sh"))

(defun hypermodern/tramp-cleanup ()
  (interactive)
  (tramp-cleanup-all-connections)
  (tramp-cleanup-all-buffers)
  (message "TRAMP nuked"))

(global-set-key (kbd "C-c T c") #'hypermodern/tramp-cleanup)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                             // misc
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package rainbow-mode
  :hook (prog-mode . rainbow-mode))

(use-package which-key
  :demand t
  :config
  (setq which-key-idle-delay 0.8)
  (which-key-mode 1))

(use-package direnv
  :demand t
  :config (direnv-mode 1))

(use-package paredit
  :hook ((emacs-lisp-mode lisp-mode scheme-mode) . paredit-mode))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                            // icons
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package nerd-icons
  :demand t)

(use-package nerd-icons-completion
  :after marginalia
  :demand t
  :config
  (nerd-icons-completion-mode)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                         // comint // asni // colors
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(add-hook 'comint-preoutput-filter-functions 'ansi-color-process-output)

;; Or more broadly, for compilation buffers too:
(require 'ansi-color)
(add-hook 'compilation-filter-hook 'ansi-color-compilation-filter)


(setq ansi-color-for-comint-mode t)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                        // dashboard
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
  :demand t
  :after nerd-icons
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
        dashboard-banner-logo-title (nth (random (length hypermodern/gibson-quotes))
                                         hypermodern/gibson-quotes)
        dashboard-center-content t
        dashboard-display-icons-p t
        dashboard-icon-type 'nerd-icons
        dashboard-set-heading-icons t
        dashboard-set-file-icons t
        dashboard-items '((recents . 5)))
  (dashboard-setup-startup-hook))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                      // keybindings
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package general
  :demand t
  :config
  (defun hypermodern/visit-init () (interactive) (find-file user-init-file))
  (defun hypermodern/kill-buffer () (interactive) (kill-buffer (current-buffer)))

  (defun hypermodern/show-current-file ()
    "Print the current buffer filename to the minibuffer."
    (interactive)
    (message (or (buffer-file-name) "[no file]")))

  (defun hypermodern/goto-definition-or-file ()
    "Go to definition of symbol, or open file at point.
Tries xref-find-definitions first for code symbols, then falls back
to finding files at point (supports relative paths, absolute paths, etc)."
    (interactive)
    (let ((file-at-point (ffap-file-at-point)))
      (condition-case nil
          ;; Try xref first (for code definitions)
          (call-interactively #'xref-goto-xref)
        (error
         ;; If xref fails, try to open file at point
         (if (and file-at-point (file-exists-p file-at-point))
             (find-file file-at-point)
           ;; If no file found, show error
           (user-error "No definition or file found at point"))))))

  (defun hypermodern/join-line-below ()
    "Join the next line to the current line (like vim's J).
Moves to end of current line, deletes newline, and collapses whitespace."
    (interactive)
    (end-of-line)
    (delete-indentation 1))

  (general-define-key

   ;; editing essentials
   "M-/" #'undo
   "C-c q" #'join-line
   "C-j" #'newline-and-indent
   "M-z" #'hypermodern/format-buffer

   ;; window navigation
   "M-N" #'windmove-right
   "M-P" #'windmove-left
   "M-R" #'hypermodern/rotate-windows
   "C-x 2" #'hypermodern/vsplit
   "C-x 3" #'hypermodern/hsplit
   "C-x k" #'hypermodern/kill-buffer

   ;; file/buffer operations
   "M-i" #'hypermodern/visit-init
   "C-c r" #'revert-buffer
   "C-c d" #'dashboard-open
   "C-c f" #'hypermodern/show-current-file

   ;; search/navigation
   "C-x C-r" #'consult-ripgrep
   "C-x C-d" #'consult-recent-file
   "C-x C-i" #'consult-info
   "C-x C-m" #'consult-man
   "C-x d" #'consult-recent-file
   "C-x f" #'consult-fd
   "C-M-r" #'consult-ripgrep

   ;; language info
   "C-c L i" #'hypermodern/language-info
   "C-c L r" #'hypermodern/show-language-registry

   ;; theme controls
   "C-c t t" #'hypermodern/apply-theme
   "C-c t d" #'hypermodern/switch-dark
   "C-c t l" #'hypermodern/switch-light
   "C-c t c" #'hypermodern/cycle-theme
   "C-c t TAB" #'hypermodern/toggle-dark-light
   "C-c t s" #'hypermodern/ui-style
   "C-c t g" #'hypermodern/ui-toggle-glow
   "C-c t p" #'hypermodern/ui-toggle-pulse
   "C-c t m" #'hypermodern/ui-menu
   ))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;;                                                    // startup
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(add-hook 'after-make-frame-functions
          (lambda (_) (hypermodern/ui-apply)))

(defun hypermodern/initialization-hook ()
  (hypermodern/apply-theme 'ono-sendai-sprawl)
  (hypermodern/ui-apply)
  (hypermodern/css-reset)
  (global-clipetty-mode))

(add-hook 'after-init-hook #'hypermodern/initialization-hook)

(provide 'init)
;;; init.el ends here
