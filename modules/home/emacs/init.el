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
;; // memory // performance // optimization
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defvar hypermodern--file-name-handler-alist file-name-handler-alist)

(setq file-name-handler-alist nil
      gc-cons-threshold most-positive-fixnum)

(add-hook 'emacs-startup-hook
          (lambda ()
            (setq file-name-handler-alist hypermodern--file-name-handler-alist
                  gc-cons-threshold (* 128 1024 1024))))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // early frame seeding (prevent PGTK pink flash)
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
;; // package // management
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(require 'package)

(setq package-archives
      '(("gnu" . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa" . "https://melpa.org/packages/")
        ("melpa-stable" . "https://stable.melpa.org/packages/")))

(setq package-archive-priorities
      '(("melpa" . 99)
        ("nongnu" . 80)
        ("gnu" . 70)
        ("melpa-stable" . 60)))

(package-initialize)

(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(require 'use-package)
(setq use-package-always-ensure t)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // forward // declarations
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
;; // PGTK Detection
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defvar hypermodern/is-pgtk
  (and (boundp 'system-configuration-features)
       (string-match-p "PGTK" system-configuration-features))
  "Non-nil if running on PGTK build of Emacs.")

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // THEME ENGINE - ZERO DEPENDENCIES
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

(defvar hypermodern/current-theme 'ono-sendai-razorgirl)

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
      (font-lock-comment-face ((,class (:foreground ,comment :slant italic))))
      (font-lock-comment-delimiter-face ((,class (:foreground ,comment :slant italic))))
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
      (org-level-1 ((,class (:foreground ,hero :weight bold :height 1.2))))
      (org-level-2 ((,class (:foreground ,link :weight bold :height 1.1))))
      (org-level-3 ((,class (:foreground ,soft :weight bold))))
      (org-level-4 ((,class (:foreground ,sky))))
      (org-level-5 ((,class (:foreground ,deep))))
      (org-level-6 ((,class (:foreground ,matrix))))
      (org-level-7 ((,class (:foreground ,ice))))
      (org-level-8 ((,class (:foreground ,fg-alt))))
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
      (markdown-header-face-1 ((,class (:foreground ,hero :weight bold :height 1.2))))
      (markdown-header-face-2 ((,class (:foreground ,link :weight bold :height 1.1))))
      (markdown-header-face-3 ((,class (:foreground ,soft :weight bold))))
      (markdown-header-face-4 ((,class (:foreground ,sky))))
      (markdown-header-face-5 ((,class (:foreground ,deep))))
      (markdown-header-face-6 ((,class (:foreground ,matrix))))
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
      (lean4-info-face ((,class (:foreground ,matrix)))))))

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
;; // css reset - color only, no typography crimes
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(defun hypermodern/css-reset ()
  "Strip typography crimes. Color only."
  (dolist (face '(italic bold bold-italic
                         font-lock-comment-face font-lock-doc-face
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
         (cursor (pcase hypermodern/ui-glow-level ('off nil) ('subtle (hypermodern/ui--color-blend accent bg 0.85)) ('neon accent) (_ nil))))
    (when (and (display-graphic-p) halo)
      (when (facep 'internal-border) (set-face-background 'internal-border halo))
      (when (facep 'fringe) (set-face-background 'fringe (hypermodern/ui--color-blend halo bg 0.55))))
    (when cursor
      (ignore-errors (set-face-background 'cursor cursor) (set-cursor-color cursor)))))

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
          (let ((_pulse-iterations 8)
                (_pulse-delay 0.04))
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
  (if hypermodern/ui-enable-pulse (hypermodern/ui--pulse-enable) (hypermodern/ui--pulse-disable))
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
  (setq hypermodern/ui-glow-level (pcase hypermodern/ui-glow-level ('off 'subtle) ('subtle 'neon) (_ 'off)))
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
;; // disable // flymake // squiggles
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

;; Disable flymake globally
(with-eval-after-load 'flymake
  (remove-hook 'flymake-diagnostic-functions 'flymake-proc-legacy-flymake))

;; Prevent flymake from starting automatically
;; (setq flymake-start-on-flymake-mode nil)
;; (add-hook 'flymake-mode-hook (lambda () (flymake-mode -1)))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // reinit // user // interface
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

(setq-default indent-tabs-mode nil
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

(use-package nerd-icons :ensure t)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // frame // discipline
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

;; (use-package shackle
;;   :ensure t
;;   :config
;;   (shackle-mode 1)
;;   (setq shackle-rules
;;         '((help-mode :other t :select t)
;;           ("\\*Help\\*" :other t :select t)
;;           ("\\*info\\*" :other t :select t)
;;           (vterm-mode :other t :select t)
;;           (compilation-mode :other t :select nil)
;;           ("\\*Warnings\\*" :align below :size 0.15 :select nil)
;;           ("\\*Backtrace\\*" :align below :size 0.25 :select t))))

(use-package popper
  :ensure t
  :bind (("C-\\" . popper-toggle)
         ("M-\\" . popper-cycle))
  :init
  (setq popper-reference-buffers
        '("\\*Messages\\*" "\\*compilation\\*" "\\*Backtrace\\*"
          "\\*rg\\*" help-mode compilation-mode))
  :config
  ;; (setq popper-display-control nil)  ;; shackle controls placement
  (popper-mode))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // window // movement
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
;; // mode // line
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package doom-modeline
  :ensure t
  :hook (after-init . doom-modeline-mode)
  :config
  (setq doom-modeline-height 20
        doom-modeline-bar-width 3
        doom-modeline-icon nil
        doom-modeline-buffer-encoding nil))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // ai - API key from env
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package gptel
  :ensure t
  :config
  (let ((api-key (getenv "OPENROUTER_API_KEY")))
    (unless api-key
      (message "[gptel] Warning: OPENROUTER_API_KEY not set"))

    (setq gptel-model 'anthropic/claude-opus-4)

    (if (fboundp 'gptel-make-openai)
        (setq gptel-backend
              (gptel-make-openai "openrouter"
                :host "openrouter.ai"
                :endpoint "/api/v1/chat/completions"
                :stream t
                :key "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["
                :models '(anthropic/claude-opus-4
                          anthropic/claude-sonnet-4
                          moonshotai/kimi-k2
                          qwen/qwen3-coder)))
      (message "[gptel] Your gptel version lacks gptel-make-openai; please update.")))

  (defun hypermodern/gptel-switch-model ()
    (interactive)
    (let* ((models '(("Opus 4" . anthropic/claude-opus-4)
                     ("Sonnet 4" . anthropic/claude-sonnet-4)
                     ("Kimi K2" . moonshotai/kimi-k2)
                     ("Qwen Coder" . qwen/qwen3-coder)))
           (choice (completing-read "Model: " (mapcar #'car models))))
      (setq gptel-model (cdr (assoc choice models)))
      (message "Model: %s" choice)))

  :bind (("C-c g g" . gptel)
         ("C-c g m" . gptel-menu)
         ("C-c g a" . hypermodern/gptel-switch-model)
         ("C-c g s" . gptel-send)
         ("C-c g k" . gptel-abort)))

(setenv "OPENROUTER_API_KEY" )

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // minibuffer // completion
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package vertico
  :ensure t
  :config
  (vertico-mode 1)
  (setq vertico-count 15
        vertico-cycle t)
  (unless hypermodern/is-pgtk
    (vertico-reverse-mode 1)))

(use-package orderless
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :ensure t
  :config (marginalia-mode 1))

(use-package consult
  :ensure t
  :bind (("C-x b" . consult-buffer)
         ;; ("C-s" . consult-line)
         ("M-g g" . consult-goto-line)
         ("M-s r" . consult-ripgrep)))

(use-package embark
  :ensure t
  :bind ("C-." . embark-act))

(use-package embark-consult
  :ensure t
  :after (embark consult))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // company
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package company
  :ensure t
  :hook (after-init . global-company-mode)
  :config
  (setq company-idle-delay 0.1
        company-minimum-prefix-length 1
        company-backends '(company-capf company-files company-dabbrev))

  ;; Force filename completion
  (defun hypermodern/company-files ()
    "Complete filenames using company-files backend."
    (interactive)
    (let ((company-backends '(company-files)))
      (company-complete)))

  :bind (("M-TAB" . company-complete-common-or-cycle)
         ("C-M-i" . company-complete-common-or-cycle)
         ("<M-tab>" . company-complete-common-or-cycle)
         ("C-c f" . hypermodern/company-files)))

(use-package yasnippet
  :ensure t
  :config (yas-global-mode 1))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // tree-sitter
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package treesit-auto
  :ensure t
  :config
  (setq treesit-auto-install 'prompt)
  (global-treesit-auto-mode 1))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // LSP
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package lsp-mode
  :ensure t
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
  :ensure t
  :after lsp-mode
  :config
  (setq lsp-ui-sideline-enable nil
        lsp-ui-doc-enable t
        lsp-ui-doc-show-with-cursor nil))


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
     :formatter nixpkgs-fmt
     :format-all-formatter nixpkgs-fmt
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

    (lean4
     :mode lean4-mode
     :extensions ("\\.lean\\'")
     :backend lsp
     :server lean
     :formatter nil
     :format-all-formatter nil
     :linter nil
     :type-checker lean
     :extra-config (lambda ()
                     (let ((toggle-fn (or (and (fboundp 'lean4-toggle-info) 'lean4-toggle-info)
                                          (and (fboundp 'lean4-info-toggle) 'lean4-info-toggle)
                                          (and (fboundp 'lean4-info-buffer-toggle) 'lean4-info-buffer-toggle))))
                       (when toggle-fn
                         (define-key lean4-mode-map (kbd "C-c C-i") toggle-fn)))))

    (bazel
     :mode bazel-mode
     :extensions (("\\.bazel\\'" . bazel-mode)
                  ("\\.bzl\\'" . bazel-mode)
                  ("\\.star\\'" . bazel-mode)
                  ("WORKSPACE\\'" . bazel-mode)
                  ("WORKSPACE\\.bazel\\'" . bazel-mode)
                  ("BUILD\\'" . bazel-mode)
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
;; // languages
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package nix-mode
  :ensure t
  :mode "\\.nix\\'"
  :hook (nix-mode . lsp-deferred))

(use-package haskell-mode
  :ensure t
  :mode "\\.hs\\'"
  :hook (haskell-mode . lsp-deferred))

(use-package lsp-haskell
  :ensure t
  :after (haskell-mode lsp-mode))

(use-package rust-mode
  :ensure t
  :mode "\\.rs\\'"
  :hook (rust-mode . lsp-deferred))

(use-package cuda-mode
  :ensure t
  :mode (("\\.cu\\'" . cuda-mode)
         ("\\.cuh\\'" . cuda-mode))
  :hook (cuda-mode . lsp-deferred))

(use-package python-mode
  :ensure nil
  :mode "\\.py\\'"
  :hook (python-mode . lsp-deferred))

(use-package typescript-ts-mode
  :ensure nil
  :mode (("\\.ts\\'" . typescript-ts-mode)
         ("\\.tsx\\'" . tsx-ts-mode))
  :hook ((typescript-ts-mode . lsp-deferred)
         (tsx-ts-mode . lsp-deferred)))

;; Lean 4
(use-package lean4-mode
  :ensure t
  :commands lean4-mode
  :mode "\\.lean\\'"
  :config
  (let ((toggle-fn (or (and (fboundp 'lean4-toggle-info) 'lean4-toggle-info)
                       (and (fboundp 'lean4-info-toggle) 'lean4-info-toggle)
                       (and (fboundp 'lean4-info-buffer-toggle) 'lean4-info-buffer-toggle))))
    (when toggle-fn
      (define-key lean4-mode-map (kbd "C-c C-i") toggle-fn))))

(use-package bazel
  :ensure t
  :mode (("\\.bazel\\'" . bazel-mode)
         ("\\.bzl\\'" . bazel-mode)
         ("\\.star\\'" . bazel-mode)
         ("WORKSPACE\\'" . bazel-mode)
         ("WORKSPACE\\.bazel\\'" . bazel-mode)
         ("BUILD\\'" . bazel-mode)
         ("BUILD\\.bazel\\'" . bazel-mode)
         ("\\.BUILD\\'" . bazel-mode)))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // formatting
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package format-all
  :ensure t
  :config
  (setq format-all-show-errors 'warnings)

  ;; Automatically configure formatters from hypermodern/language-registry
  (setq format-all-formatters
        (let ((formatters '()))
          (dolist (entry hypermodern/language-registry)
            (let* ((config (cdr entry))
                   (mode (plist-get config :mode))
                   (formatter (plist-get config :format-all-formatter))
                   (extra-modes (plist-get config :extra-modes)))
              ;; Add formatter for primary mode
              (when (and mode formatter)
                (push (cons mode formatter) formatters))
              ;; Add formatter for extra modes (e.g., tsx-ts-mode for typescript)
              (when extra-modes
                (dolist (extra-mode extra-modes)
                  (when formatter
                    (push (cons extra-mode formatter) formatters))))))
          formatters))

  (defun hypermodern/format-buffer ()
    "Format buffer without prompting for formatter."
    (interactive)
    (format-all-buffer nil))

  :bind ("M-z" . hypermodern/format-buffer))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // magit
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package transient
  :ensure t)

(use-package magit
  :ensure t
  :bind ("C-x g" . magit))

(use-package forge
  :ensure t
  :after magit)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // terminals
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package vterm
  :ensure t
  :commands vterm
  :config
  (setq vterm-environment '("COLORTERM=truecolor"))
  :hook (vterm-mode . (lambda ()
                        (hl-line-mode -1)
                        (define-key vterm-mode-map (kbd "M-N") #'windmove-right)
                        (define-key vterm-mode-map (kbd "M-P") #'windmove-left))))

(use-package eat
  :ensure t
  :commands eat)

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // tramp - bulletproof sshx
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package tramp
  :ensure nil
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
;; // misc
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package rainbow-mode
  :ensure t
  :hook (prog-mode . rainbow-mode))

(use-package which-key
  :ensure t
  :config
  (setq which-key-idle-delay 0.8)
  (which-key-mode 1))

(use-package direnv
  :ensure t
  :config (direnv-mode 1))

(use-package paredit
  :ensure t
  :hook ((emacs-lisp-mode lisp-mode scheme-mode) . paredit-mode))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // dashboard
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
  :ensure t

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
        dashboard-items '((recents . 5)))
  (dashboard-setup-startup-hook))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // keybindings
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(use-package general
  :ensure t
  :config
  (defun hypermodern/visit-init () (interactive) (find-file user-init-file))
  (defun hypermodern/kill-buffer () (interactive) (kill-buffer (current-buffer)))

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

  (general-define-key
   "M-/" #'undo
   "M-N" #'windmove-right
   "M-P" #'windmove-left
   "M-i" #'hypermodern/visit-init
   "M-R" #'hypermodern/rotate-windows
;  "M-." #'hypermodern/goto-definition-or-file

   "C-x 2" #'hypermodern/vsplit
   "C-x 3" #'hypermodern/hsplit
   "C-x k" #'hypermodern/kill-buffer
   "C-c r" #'revert-buffer
   
   "C-c L i" #'hypermodern/language-info
   "C-c L r" #'hypermodern/show-language-registry

   "C-c t t" #'hypermodern/apply-theme
   "C-c t d" #'hypermodern/switch-dark
   "C-c t l" #'hypermodern/switch-light
   "C-c t c" #'hypermodern/cycle-theme
   "C-c t TAB" #'hypermodern/toggle-dark-light
   "C-c t s" #'hypermodern/ui-style
   "C-c t g" #'hypermodern/ui-toggle-glow
   "C-c t p" #'hypermodern/ui-toggle-pulse
   "C-c t m" #'hypermodern/ui-menu

   "C-x C-r" #'consult-ripgrep
   "C-x C-d" #'consult-recent-file
   "C-x C-i" #'consult-info
   "C-x C-m" #'consult-man
   ))

;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
;; // startup
;; ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

(add-hook 'after-make-frame-functions
          (lambda (_) (hypermodern/ui-apply)))

(defun hypermodern/initialization-hook ()
  (hypermodern/apply-theme 'ono-sendai-razorgirl)
  (hypermodern/ui-apply)
  (hypermodern/css-reset)
  (recentf-mode)
  (vertico-reverse-mode)
  (global-clipetty-mode)
  )

(add-hook 'after-init-hook #'hypermodern/initialization-hook)

(provide 'init)
;;; init.el ends here
