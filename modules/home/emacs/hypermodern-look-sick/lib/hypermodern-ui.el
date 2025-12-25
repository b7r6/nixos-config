;;; hypermodern-ui.el --- sick but minimal visuals (glow-up edition) -*- lexical-binding: t; -*-
;;
;; This file is meant to be loaded early-ish (after theme + modeline packages exist),
;; but it is safe to load even if optional packages are missing.
;;
;; Philosophy:
;;   - default: minimal and quiet
;;   - variations: a whole universe, but behind a single menu
;;   - glow: subtle by default; can go neon when you ask
;;
;; Entry points:
;;   M-x hypermodern/ui-menu
;;   M-x hypermodern/ui-style
;;   M-x hypermodern/ui-theme
;;   M-x hypermodern/ui-apply
;;
;; Persisting:
;;   M-x hypermodern/ui-save  (writes choices to your custom-file)
;;

(require 'cl-lib)
(require 'seq)

(defgroup hypermodern-ui nil
  "Minimal cyber aesthetics with a universe of variations."
  :group 'faces)

(defcustom hypermodern/ui-theme 'base16-stylix
  "Theme symbol to load (if available)."
  :type 'symbol)

(defcustom hypermodern/ui-density 'tight
  "UI density preset."
  :type '(choice (const :tag "Tight (minimal)" tight)
                 (const :tag "Normal" normal)
                 (const :tag "Comfy" comfy)
                 (const :tag "Cinema" cinema)))

(defcustom hypermodern/ui-signal 'minimal
  "How much UI signal you want in the modeline and chrome."
  :type '(choice (const :tag "Minimal" minimal)
                 (const :tag "Normal" normal)
                 (const :tag "Loud" loud)))

(defcustom hypermodern/ui-glow-level 'subtle
  "Glow intensity.

This is intentionally not a theme. It's a thin aesthetic layer:
- frame halo tint (internal border) when available
- cursor accent
- show-paren + pulse highlight tuned to your palette

Use `off` for pure minimal, `subtle` for daily-driver glow,
`neon` when you want it to look like a control panel."
  :type '(choice (const :tag "Off" off)
                 (const :tag "Subtle" subtle)
                 (const :tag "Neon" neon)))

(defcustom hypermodern/ui-glow-halo 'auto
  "Frame halo policy.

Only applied when `hypermodern/ui-glow-level` is not `off`.
- off: never increase internal border width
- auto: ensure a small halo is visible even in tight density
- integer: explicit halo width in pixels"
  :type '(choice (const :tag "Off" off)
                 (const :tag "Auto" auto)
                 (integer :tag "Width (px)")))

(defcustom hypermodern/ui-enable-pulse t
  "If non-nil, pulse the current line after selected jump/move commands.

This is a *glow* feature: it makes navigation feel intentional without
adding persistent UI noise."
  :type 'boolean)

(defcustom hypermodern/ui-pulse-commands
  '(other-window
    windmove-left windmove-right windmove-up windmove-down
    xref-find-definitions xref-find-references xref-go-back
    imenu
    goto-line
    consult-line consult-ripgrep consult-buffer consult-imenu
    consult-goto-line)
  "Commands that should trigger a pulse highlight when `hypermodern/ui-enable-pulse`.

Note: entries that don't exist are harmless."
  :type '(repeat symbol))

(defcustom hypermodern/ui-cursor-style nil
  "Cursor style override when glow is on.

nil means: don't touch cursor-type.
Otherwise: bar/box/hbar."
  :type '(choice (const :tag "Don't touch" nil)
                 (const :tag "Bar" bar)
                 (const :tag "Box" box)
                 (const :tag "HBar" hbar)))

(defcustom hypermodern/ui-font-preset 'auto
  "Font preset selection."
  :type '(choice (const :tag "Auto (first available)" auto)
                 (const :tag "Berkeley Mono" berkeley)
                 (const :tag "Iosevka" iosevka)
                 (const :tag "JetBrains Mono" jetbrains)
                 (const :tag "System default" system)))

(defcustom hypermodern/ui-font-size 100
  "Default font size (face :height). 100 = 10pt-ish."
  :type 'integer)

(defcustom hypermodern/ui-variable-font-size 110
  "Variable pitch font size."
  :type 'integer)

(defcustom hypermodern/ui-padding nil
  "Override internal border width. If nil, density decides."
  :type '(choice (const :tag "Use density default" nil)
                 (integer :tag "Pixels")))

(defcustom hypermodern/ui-alpha 100
  "Frame background alpha (0-100). 100 = opaque."
  :type 'integer)

(defcustom hypermodern/ui-enable-transparency nil
  "If non-nil, apply `hypermodern/ui-alpha` when in GUI frames."
  :type 'boolean)

(defcustom hypermodern/ui-enable-ligatures nil
  "If non-nil, try to enable ligatures (requires ligature.el)."
  :type 'boolean)

(defcustom hypermodern/ui-enable-dim nil
  "If non-nil, try to dim inactive windows (requires dimmer.el)."
  :type 'boolean)

(defcustom hypermodern/ui-enable-solaire nil
  "If non-nil, try to subtly differentiate special buffers (requires solaire-mode)."
  :type 'boolean)

(defcustom hypermodern/ui-enable-writing-mode nil
  "If non-nil, enable a low-distraction writing layer for text/org."
  :type 'boolean)

(defconst hypermodern/ui--font-presets
  '((auto
     :mono ("Berkeley Mono" "Iosevka Term" "Iosevka Fixed" "JetBrains Mono"
            "Fira Code" "SF Mono" "Monaco" "DejaVu Sans Mono")
     :variable ("Berkeley Mono" "Iosevka Aile" "Inter" "SF Pro Text"
                "Noto Sans" "DejaVu Sans"))
    (berkeley
     :mono ("Berkeley Mono")
     :variable ("Berkeley Mono" "Inter" "SF Pro Text" "Noto Sans"))
    (iosevka
     :mono ("Iosevka Term" "Iosevka Fixed" "Iosevka")
     :variable ("Iosevka Aile" "Inter" "Noto Sans"))
    (jetbrains
     :mono ("JetBrains Mono" "JetBrainsMono Nerd Font" "JetBrainsMono NF")
     :variable ("Inter" "Noto Sans" "SF Pro Text"))
    (system
     :mono nil
     :variable nil))
  "Font search lists. First installed wins.")

(defconst hypermodern/ui--style-presets
  ;; A curated “universe”: palettes (ono-sendai variants) x density x signal.
  ;; These don't assume the themes exist; missing themes are skipped gracefully.
  '(
    ;; pure minimal baseline
    (:name "Minimal / Stylix" :theme base16-stylix :density tight :signal minimal :font auto :alpha 100
           :glow off :pulse nil :halo off)

    ;; daily driver glow-up (still minimal, just intentional)
    (:name "Minimal / Stylix / Glow" :theme base16-stylix :density tight :signal minimal :font auto :alpha 100
           :glow subtle :pulse t :halo auto)

    ;; neon control room (still disciplined: no confetti)
    (:name "Minimal / Stylix / Neon" :theme base16-stylix :density tight :signal loud :font auto :alpha 97
           :trans t :glow neon :pulse t :halo auto :dim t)

    ;; ono-sendai family (expects you to package those themes via Nix or otherwise)
    (:name "Ono-Sendai / GitHub (robust)" :theme base16-ono-sendai-github :density tight :signal minimal :font auto :alpha 100
           :glow subtle :pulse t :halo auto)

    (:name "Ono-Sendai / Tuned (daily driver)" :theme base16-ono-sendai-tuned :density tight :signal minimal :font auto :alpha 100
           :glow subtle :pulse t :halo auto)

    (:name "Ono-Sendai / Sprawl" :theme base16-ono-sendai-sprawl :density normal :signal minimal :font auto :alpha 100
           :glow subtle :pulse t :halo auto)

    (:name "Ono-Sendai / Razor Girl" :theme base16-ono-sendai-razorgirl :density tight :signal normal :font auto :alpha 100
           :glow subtle :pulse t :halo auto)

    (:name "Ono-Sendai / Memphis (OLED black)" :theme base16-ono-sendai-memphis :density tight :signal minimal :font auto :alpha 98
           :trans t :glow subtle :pulse t :halo auto)

    (:name "Ono-Sendai / Spectrum (hue discipline)" :theme base16-ono-sendai-spectrum :density normal :signal normal :font auto :alpha 100
           :glow subtle :pulse t :halo auto)

    ;; typography-first variations
    (:name "Iosevka / Tight / Glow" :theme base16-stylix :density tight :signal minimal :font iosevka :alpha 100
           :glow subtle :pulse t :halo auto)

    (:name "JetBrains / Normal / Glow" :theme base16-stylix :density normal :signal normal :font jetbrains :alpha 100
           :glow subtle :pulse t :halo auto)

    (:name "Berkeley / Comfy / Glow" :theme base16-stylix :density comfy :signal minimal :font berkeley :alpha 100
           :glow subtle :pulse t :halo auto)

    ;; writing + reading
    (:name "Writing / Comfy / Glow" :theme base16-stylix :density comfy :signal minimal :font auto :alpha 100
           :writing t :glow subtle :pulse nil :halo auto)

    (:name "Cinema / Reading Mode" :theme base16-stylix :density cinema :signal minimal :font auto :alpha 100
           :writing t :glow subtle :pulse nil :halo auto)

    ;; ghost mode: dim + translucent + halo
    (:name "Ghost / Sprawl" :theme base16-ono-sendai-sprawl :density normal :signal minimal :font auto :alpha 96
           :trans t :dim t :solaire t :glow subtle :pulse t :halo auto)

    ;; phosphor mode: neon but restrained
    (:name "Phosphor / Memphis" :theme base16-ono-sendai-memphis :density tight :signal loud :font auto :alpha 95
           :trans t :dim t :glow neon :pulse t :halo auto)
    )
  "Curated style universe.")

;; ----------------------------
;; Helpers
;; ----------------------------

(defun hypermodern/ui--font-installed-p (font)
  (and (stringp font)
       (member font (font-family-list))))

(defun hypermodern/ui--first-font (fonts)
  (when (listp fonts)
    (seq-find #'hypermodern/ui--font-installed-p fonts)))

(defun hypermodern/ui--face-bg (face)
  (let ((bg (face-background face nil t)))
    (when (and (stringp bg)
               (not (string-match-p "unspecified" bg)))
      bg)))

(defun hypermodern/ui--face-fg (face)
  (let ((fg (face-foreground face nil t)))
    (when (and (stringp fg)
               (not (string-match-p "unspecified" fg)))
      fg)))

(defun hypermodern/ui--color-blend (c1 c2 alpha)
  "Blend color C1 onto C2 by ALPHA (0..1)."
  (when (and (stringp c1) (stringp c2)
             (fboundp 'color-name-to-rgb)
             (fboundp 'color-rgb-to-hex))
    (require 'color)
    (let ((r1 (color-name-to-rgb c1))
          (r2 (color-name-to-rgb c2)))
      (when (and r1 r2)
        (apply #'color-rgb-to-hex
               (cl-mapcar (lambda (a b) (+ (* alpha a) (* (- 1 alpha) b)))
                          r1 r2))))))

(defun hypermodern/ui--theme-available-p (theme)
  (and (symbolp theme)
       (memq theme (custom-available-themes))))

(defun hypermodern/ui--disable-themes ()
  (mapc #'disable-theme custom-enabled-themes))

(defun hypermodern/ui--set-frame-param (key val)
  "Set frame parameter KEY to VAL for current and future frames."
  (set-frame-parameter nil key val)
  (setq default-frame-alist (assq-delete-all key default-frame-alist))
  (add-to-list 'default-frame-alist (cons key val)))

(defun hypermodern/ui--accent-color ()
  "Best-effort accent color derived from the current theme." 
  (or (hypermodern/ui--face-fg 'link)
      (hypermodern/ui--face-fg 'font-lock-keyword-face)
      (hypermodern/ui--face-fg 'success)
      (hypermodern/ui--face-fg 'warning)
      (hypermodern/ui--face-fg 'error)
      ;; fallback: your ono-sendai hero
      "#54aeff"))

(defun hypermodern/ui--glow-alpha ()
  (pcase hypermodern/ui-glow-level
    ('off 0.0)
    ('subtle 0.08)
    ('neon 0.16)
    (_ 0.0)))

(defun hypermodern/ui--glow-alpha-strong ()
  (pcase hypermodern/ui-glow-level
    ('off 0.0)
    ('subtle 0.14)
    ('neon 0.22)
    (_ 0.0)))

(defun hypermodern/ui--halo-min-width ()
  "Minimum halo width to guarantee a visible frame halo when asked." 
  (pcase hypermodern/ui-density
    ('tight 8)
    ('normal 10)
    ('comfy 12)
    ('cinema 16)
    (_ 8)))

;; ----------------------------
;; Apply: fonts, density, theme, modeline tuning
;; ----------------------------

(defun hypermodern/ui--apply-fonts ()
  "Apply current font preset."
  (let* ((preset (assq hypermodern/ui-font-preset hypermodern/ui--font-presets))
         (mono-list (plist-get (cdr preset) :mono))
         (var-list  (plist-get (cdr preset) :variable))
         (mono (or (hypermodern/ui--first-font mono-list) (and (eq hypermodern/ui-font-preset 'system) nil)))
         (var  (or (hypermodern/ui--first-font var-list) mono)))
    (when mono
      (set-face-attribute 'default nil :family mono :height hypermodern/ui-font-size)
      (set-face-attribute 'fixed-pitch nil :family mono :height hypermodern/ui-font-size))
    (when var
      (set-face-attribute 'variable-pitch nil :family var :height hypermodern/ui-variable-font-size))))

(defun hypermodern/ui--density-values (density)
  (pcase density
    ('tight  (list :pad 0  :fringe '(8 . 8)  :line-spacing 0))
    ('normal (list :pad 10 :fringe '(10 . 10) :line-spacing 0))
    ('comfy  (list :pad 16 :fringe '(12 . 12) :line-spacing 2))
    ('cinema (list :pad 28 :fringe '(14 . 14) :line-spacing 4))
    (_       (list :pad 0  :fringe '(8 . 8)  :line-spacing 0))))

(defun hypermodern/ui--apply-density ()
  "Apply density: padding, fringe, line spacing.

Also: if glow halo is enabled, ensure internal border is thick enough to show it."
  (let* ((vals (hypermodern/ui--density-values hypermodern/ui-density))
         (base-pad (or hypermodern/ui-padding (plist-get vals :pad)))
         (halo-pad
          (if (eq hypermodern/ui-glow-level 'off)
              0
            (pcase hypermodern/ui-glow-halo
              ('off 0)
              ('auto (hypermodern/ui--halo-min-width))
              ((pred integerp) hypermodern/ui-glow-halo)
              (_ 0))))
         (pad (max base-pad halo-pad))
         (fr (plist-get vals :fringe))
         (ls (plist-get vals :line-spacing)))
    (fringe-mode fr)
    (setq-default line-spacing ls)
    (hypermodern/ui--set-frame-param 'internal-border-width pad)))

(defun hypermodern/ui--apply-transparency ()
  "Apply transparency if enabled and in GUI."
  (when (and hypermodern/ui-enable-transparency (display-graphic-p))
    ;; Emacs 29+: alpha-background. Older builds: alpha (active . inactive).
    (ignore-errors
      (hypermodern/ui--set-frame-param 'alpha-background hypermodern/ui-alpha))
    (ignore-errors
      (hypermodern/ui--set-frame-param 'alpha (cons hypermodern/ui-alpha hypermodern/ui-alpha)))))

(defun hypermodern/ui--post-theme-tuning ()
  "Make it look intentional without fighting the theme." 
  ;; Dividers: align window-divider + vertical-border.
  (let* ((vb (or (hypermodern/ui--face-fg 'vertical-border)
                 (hypermodern/ui--face-fg 'shadow)))
         (ml (hypermodern/ui--face-bg 'mode-line-inactive))
         (bg (hypermodern/ui--face-bg 'default))
         (divider (or vb (and ml bg (hypermodern/ui--color-blend ml bg 0.55)) vb)))
    (when divider
      (set-face-foreground 'vertical-border divider)
      (when (facep 'window-divider)
        (set-face-foreground 'window-divider divider)
        (set-face-foreground 'window-divider-first-pixel divider)
        (set-face-foreground 'window-divider-last-pixel divider))))

  ;; HL line: subtle, derived from theme colors.
  (let* ((bg (hypermodern/ui--face-bg 'default))
         (alt (or (hypermodern/ui--face-bg 'mode-line-inactive)
                  (hypermodern/ui--face-bg 'region)))
         (hl (and bg alt (hypermodern/ui--color-blend alt bg 0.15))))
    (when hl
      (set-face-attribute 'hl-line nil :background hl :extend t)))

  ;; Region: slightly more “glass” than default, but still quiet.
  (let* ((bg (hypermodern/ui--face-bg 'default))
         (accent (hypermodern/ui--accent-color))
         (reg (and bg accent (hypermodern/ui--color-blend accent bg 0.10))))
    (when reg
      (set-face-attribute 'region nil :background reg :extend t))))

(defun hypermodern/ui--apply-theme ()
  "Load theme if available, else do nothing." 
  (when (hypermodern/ui--theme-available-p hypermodern/ui-theme)
    (hypermodern/ui--disable-themes)
    (load-theme hypermodern/ui-theme t))
  (hypermodern/ui--post-theme-tuning))

(defun hypermodern/ui--apply-modeline ()
  "Tune doom-modeline to match signal + density." 
  (when (featurep 'doom-modeline)
    ;; Tie height to density a bit.
    (setq doom-modeline-height
          (pcase hypermodern/ui-density
            ('tight 18) ('normal 20) ('comfy 22) ('cinema 26) (_ 20)))

    (pcase hypermodern/ui-signal
      ('minimal
       (setq doom-modeline-icon nil
             doom-modeline-major-mode-icon nil
             doom-modeline-minor-modes nil
             doom-modeline-buffer-encoding nil
             doom-modeline-checker-simple-format t
             doom-modeline-modal nil
             doom-modeline-enable-word-count nil))
      ('normal
       (setq doom-modeline-icon (display-graphic-p)
             doom-modeline-major-mode-icon (display-graphic-p)
             doom-modeline-minor-modes nil
             doom-modeline-buffer-encoding nil
             doom-modeline-checker-simple-format t
             doom-modeline-modal nil
             doom-modeline-enable-word-count nil))
      ('loud
       (setq doom-modeline-icon (display-graphic-p)
             doom-modeline-major-mode-icon (display-graphic-p)
             doom-modeline-minor-modes t
             doom-modeline-buffer-encoding t
             doom-modeline-checker-simple-format nil
             doom-modeline-modal t
             doom-modeline-enable-word-count t)))

    ;; Re-enable to apply all settings reliably.
    (doom-modeline-mode -1)
    (doom-modeline-mode 1)
    (force-mode-line-update t)))

(defun hypermodern/ui--maybe-toggle (library fn enabled)
  (when (require library nil 'noerror)
    (funcall fn (if enabled 1 -1))))

;; Writing layer: minimal, no gimmicks unless packages exist.
(defun hypermodern/ui--writing-enable ()
  (when (derived-mode-p 'text-mode 'org-mode 'markdown-mode)
    (visual-line-mode 1)
    (setq-local line-spacing (max (or line-spacing 0) 2))
    (when (fboundp 'variable-pitch-mode)
      (variable-pitch-mode 1))
    (when (require 'mixed-pitch nil 'noerror)
      (mixed-pitch-mode 1))
    (when (require 'olivetti nil 'noerror)
      (setq olivetti-body-width 90)
      (olivetti-mode 1))
    (when (require 'org-modern nil 'noerror)
      (org-modern-mode 1))))

(defun hypermodern/ui--writing-disable ()
  (when (derived-mode-p 'text-mode 'org-mode 'markdown-mode)
    (when (fboundp 'visual-line-mode) (visual-line-mode -1))
    (when (fboundp 'variable-pitch-mode) (variable-pitch-mode -1))
    (when (fboundp 'mixed-pitch-mode) (mixed-pitch-mode -1))
    (when (fboundp 'olivetti-mode) (olivetti-mode -1))
    (when (fboundp 'org-modern-mode) (org-modern-mode -1))))

(define-minor-mode hypermodern/ui-writing-mode
  "Local writing layer." 
  :init-value nil
  :lighter " ✍"
  (if hypermodern/ui-writing-mode
      (hypermodern/ui--writing-enable)
    (hypermodern/ui--writing-disable)))

(define-globalized-minor-mode hypermodern/ui-writing-global-mode
  hypermodern/ui-writing-mode
  (lambda ()
    (when hypermodern/ui-enable-writing-mode
      (hypermodern/ui-writing-mode 1))))

;; Ligatures (optional).
(defun hypermodern/ui--ligatures (on)
  (when (require 'ligature nil 'noerror)
    ;; Conservative set: reads well, doesn't turn code into emoji soup.
    (ligature-set-ligatures 't
                            '("==" "===" "!=" "!==" "->" "=>"
                              "<-" "<=" ">=" "&&" "||"
                              "::" ":=" ">>" "<<" ">>=" "<<="
                              "++" "--" "/*" "*/" "/**" "*/"
                              "#(" "#{" "#[" ";;" "..." "??"))
    (if on
        (global-ligature-mode 1)
      (global-ligature-mode -1))))

;; ----------------------------
;; Glow + pulse
;; ----------------------------

(defvar hypermodern/ui--pulse-hook-installed nil)

(defun hypermodern/ui--pulse-post-command ()
  "Pulse the current line when `this-command` is in `hypermodern/ui-pulse-commands`."
  (when (and hypermodern/ui-enable-pulse
             (memq this-command hypermodern/ui-pulse-commands))
    (when (require 'pulse nil 'noerror)
      (ignore-errors
        (pulse-momentary-highlight-one-line (point))))))

(defun hypermodern/ui--pulse-enable ()
  (unless hypermodern/ui--pulse-hook-installed
    (add-hook 'post-command-hook #'hypermodern/ui--pulse-post-command)
    (setq hypermodern/ui--pulse-hook-installed t)))

(defun hypermodern/ui--pulse-disable ()
  (when hypermodern/ui--pulse-hook-installed
    (remove-hook 'post-command-hook #'hypermodern/ui--pulse-post-command)
    (setq hypermodern/ui--pulse-hook-installed nil)))

(defun hypermodern/ui--apply-glow ()
  "Apply glow layer (halo, cursor, paren match, pulse colors)."
  (let* ((bg (or (hypermodern/ui--face-bg 'default) "#000000"))
         (accent (hypermodern/ui--accent-color))
         (a (hypermodern/ui--glow-alpha))
         (a-strong (hypermodern/ui--glow-alpha-strong))
         (halo (and (> a 0.0) (hypermodern/ui--color-blend accent bg a)))
         (halo-strong (and (> a-strong 0.0) (hypermodern/ui--color-blend accent bg a-strong)))
         (cursor (pcase hypermodern/ui-glow-level
                   ('off nil)
                   ('subtle (hypermodern/ui--color-blend accent bg 0.85))
                   ('neon accent)
                   (_ nil)))
         (bar (pcase hypermodern/ui-glow-level
                ('off nil)
                ('subtle (hypermodern/ui--color-blend accent bg 0.92))
                ('neon accent)
                (_ nil))))

    ;; Frame halo tint (GUI only).
    (when (and (display-graphic-p) halo)
      (when (facep 'internal-border)
        (set-face-background 'internal-border halo))

      ;; Optional: fringe as a slight inset (very subtle).
      (when (facep 'fringe)
        (set-face-background 'fringe (hypermodern/ui--color-blend halo bg 0.55)))

      ;; Cursor glow.
      (when cursor
        (ignore-errors
          (set-face-background 'cursor cursor)
          (set-cursor-color cursor))
        (when hypermodern/ui-cursor-style
          (setq-default cursor-type hypermodern/ui-cursor-style))))

    ;; show-paren: make match feel like a holographic bracket.
    (when halo-strong
      (set-face-attribute 'show-paren-match nil
                          :background halo-strong
                          :foreground nil
                          :weight 'semi-bold
                          :underline nil)
      (set-face-attribute 'show-paren-mismatch nil
                          :background (hypermodern/ui--color-blend (or (hypermodern/ui--face-fg 'error) "#ff5370") bg 0.18)
                          :foreground nil
                          :weight 'bold))

    ;; Pulse faces.
    (when (and (> a 0.0) (facep 'pulse-highlight-face))
      (set-face-attribute 'pulse-highlight-face nil :background (hypermodern/ui--color-blend accent bg 0.10) :extend t))
    (when (and (> a 0.0) (facep 'pulse-highlight-start-face))
      (set-face-attribute 'pulse-highlight-start-face nil :background (hypermodern/ui--color-blend accent bg 0.16) :extend t))

    ;; doom-modeline bar “laser line”.
    (when (and bar (featurep 'doom-modeline))
      (setq doom-modeline-bar-width (pcase hypermodern/ui-glow-level
                                      ('subtle 3)
                                      ('neon 4)
                                      (_ 1)))
      (when (facep 'doom-modeline-bar)
        (set-face-background 'doom-modeline-bar bar))
      (when (facep 'doom-modeline-bar-inactive)
        (set-face-background 'doom-modeline-bar-inactive (hypermodern/ui--color-blend bar bg 0.25))))))

;; ----------------------------
;; Main apply / init
;; ----------------------------

(defun hypermodern/ui-apply ()
  "Apply all UI settings (theme, density, fonts, modeline, toggles)."
  (interactive)
  (hypermodern/ui--apply-density)
  (hypermodern/ui--apply-fonts)
  (hypermodern/ui--apply-transparency)
  (hypermodern/ui--apply-theme)
  (hypermodern/ui--apply-modeline)

  ;; Optional extras (quiet by default)
  (when (and hypermodern/ui-enable-dim (require 'dimmer nil 'noerror))
    ;; Keep dim subtle; glow does the emphasis.
    (setq dimmer-fraction (pcase hypermodern/ui-glow-level
                            ('neon 0.28)
                            ('subtle 0.20)
                            (_ 0.15)))
    (dimmer-mode 1))
  (when (and (not hypermodern/ui-enable-dim) (featurep 'dimmer))
    (dimmer-mode -1))

  (hypermodern/ui--maybe-toggle 'solaire-mode 'solaire-global-mode hypermodern/ui-enable-solaire)

  (setq hypermodern/ui-enable-writing-mode (and hypermodern/ui-enable-writing-mode t))
  (if hypermodern/ui-enable-writing-mode
      (hypermodern/ui-writing-global-mode 1)
    (hypermodern/ui-writing-global-mode -1))

  (hypermodern/ui--ligatures hypermodern/ui-enable-ligatures)

  ;; Glow / pulse layer (after theme + modeline)
  (hypermodern/ui--apply-glow)

  (if hypermodern/ui-enable-pulse
      (hypermodern/ui--pulse-enable)
    (hypermodern/ui--pulse-disable))

  (message "[hypermodern-ui] applied: theme=%s density=%s signal=%s glow=%s font=%s"
           hypermodern/ui-theme hypermodern/ui-density hypermodern/ui-signal
           hypermodern/ui-glow-level hypermodern/ui-font-preset))

(defun hypermodern/ui-init ()
  "Initialize hypermodern-ui and keep it applied across new frames." 
  (hypermodern/ui-apply)
  (add-hook 'after-make-frame-functions
            (lambda (_f) (with-selected-frame _f (hypermodern/ui-apply)))))

;; ----------------------------
;; Interactive: theme + style selection
;; ----------------------------

(defun hypermodern/ui--themes-universe ()
  "Return a curated list of themes that actually exist." 
  (let* ((all (custom-available-themes))
         (pred (lambda (t)
                 (let ((s (symbol-name t)))
                   (or (eq t 'base16-stylix)
                       (string-prefix-p "base16-ono-sendai-" s)
                       (string-prefix-p "base16-" s)
                       (string-prefix-p "modus-" s)
                       (string-prefix-p "ef-" s)
                       (string-prefix-p "doom-" s)
                       (string-prefix-p "catppuccin-" s))))))
    (seq-filter pred all)))

(defun hypermodern/ui-theme ()
  "Pick a theme from your installed universe." 
  (interactive)
  (let* ((themes (hypermodern/ui--themes-universe))
         (choice (intern (completing-read "Theme: " (mapcar #'symbol-name themes) nil t))))
    (setq hypermodern/ui-theme choice)
    (hypermodern/ui-apply)))

(defun hypermodern/ui-style ()
  "Pick a full style preset (theme + density + signal + font + glow extras)." 
  (interactive)
  (let* ((names (mapcar (lambda (p) (plist-get p :name)) hypermodern/ui--style-presets))
         (choice (completing-read "Style: " names nil t))
         (preset (seq-find (lambda (p) (string= (plist-get p :name) choice))
                           hypermodern/ui--style-presets)))
    (when preset
      (when (plist-member preset :theme)   (setq hypermodern/ui-theme (plist-get preset :theme)))
      (when (plist-member preset :density) (setq hypermodern/ui-density (plist-get preset :density)))
      (when (plist-member preset :signal)  (setq hypermodern/ui-signal (plist-get preset :signal)))
      (when (plist-member preset :font)    (setq hypermodern/ui-font-preset (plist-get preset :font)))
      (when (plist-member preset :alpha)   (setq hypermodern/ui-alpha (plist-get preset :alpha)))
      (when (plist-member preset :pad)     (setq hypermodern/ui-padding (plist-get preset :pad)))
      (when (plist-member preset :writing) (setq hypermodern/ui-enable-writing-mode (plist-get preset :writing)))

      ;; glow extras
      (when (plist-member preset :glow)    (setq hypermodern/ui-glow-level (plist-get preset :glow)))
      (when (plist-member preset :halo)    (setq hypermodern/ui-glow-halo (plist-get preset :halo)))
      (when (plist-member preset :pulse)   (setq hypermodern/ui-enable-pulse (plist-get preset :pulse)))
      (when (plist-member preset :dim)     (setq hypermodern/ui-enable-dim (plist-get preset :dim)))
      (when (plist-member preset :solaire) (setq hypermodern/ui-enable-solaire (plist-get preset :solaire)))
      (when (plist-member preset :trans)   (setq hypermodern/ui-enable-transparency (plist-get preset :trans))))
    (hypermodern/ui-apply)))

(defun hypermodern/ui-density (density)
  "Set density." 
  (interactive
   (list (intern (completing-read "Density: " '("tight" "normal" "comfy" "cinema") nil t))))
  (setq hypermodern/ui-density density)
  (hypermodern/ui-apply))

(defun hypermodern/ui-signal (signal)
  "Set signal level." 
  (interactive
   (list (intern (completing-read "Signal: " '("minimal" "normal" "loud") nil t))))
  (setq hypermodern/ui-signal signal)
  (hypermodern/ui-apply))

(defun hypermodern/ui-font (preset)
  "Set font preset." 
  (interactive
   (list (intern (completing-read "Font: " '("auto" "berkeley" "iosevka" "jetbrains" "system") nil t))))
  (setq hypermodern/ui-font-preset preset)
  (hypermodern/ui-apply))

(defun hypermodern/ui-glow (level)
  "Set glow intensity." 
  (interactive
   (list (intern (completing-read "Glow: " '("off" "subtle" "neon") nil t))))
  (setq hypermodern/ui-glow-level level)
  (hypermodern/ui-apply))

(defun hypermodern/ui-toggle-glow ()
  "Cycle glow: off → subtle → neon → off." 
  (interactive)
  (setq hypermodern/ui-glow-level
        (pcase hypermodern/ui-glow-level
          ('off 'subtle)
          ('subtle 'neon)
          (_ 'off)))
  (hypermodern/ui-apply)
  (message "Glow: %s" hypermodern/ui-glow-level))

(defun hypermodern/ui-toggle-pulse ()
  (interactive)
  (setq hypermodern/ui-enable-pulse (not hypermodern/ui-enable-pulse))
  (hypermodern/ui-apply)
  (message "Pulse: %s" (if hypermodern/ui-enable-pulse "on" "off")))

(defun hypermodern/ui-toggle-transparency ()
  (interactive)
  (setq hypermodern/ui-enable-transparency (not hypermodern/ui-enable-transparency))
  (hypermodern/ui-apply)
  (message "Transparency: %s" (if hypermodern/ui-enable-transparency "on" "off")))

(defun hypermodern/ui-toggle-writing ()
  (interactive)
  (setq hypermodern/ui-enable-writing-mode (not hypermodern/ui-enable-writing-mode))
  (hypermodern/ui-apply)
  (message "Writing mode: %s" (if hypermodern/ui-enable-writing-mode "on" "off")))

(defun hypermodern/ui-toggle-dim ()
  (interactive)
  (setq hypermodern/ui-enable-dim (not hypermodern/ui-enable-dim))
  (hypermodern/ui-apply)
  (message "Dim inactive windows: %s" (if hypermodern/ui-enable-dim "on" "off")))

(defun hypermodern/ui-toggle-solaire ()
  (interactive)
  (setq hypermodern/ui-enable-solaire (not hypermodern/ui-enable-solaire))
  (hypermodern/ui-apply)
  (message "Solaire: %s" (if hypermodern/ui-enable-solaire "on" "off")))

(defun hypermodern/ui-toggle-ligatures ()
  (interactive)
  (setq hypermodern/ui-enable-ligatures (not hypermodern/ui-enable-ligatures))
  (hypermodern/ui-apply)
  (message "Ligatures: %s" (if hypermodern/ui-enable-ligatures "on" "off")))

(defun hypermodern/ui-save ()
  "Persist current choices to `custom-file`." 
  (interactive)
  (dolist (v '(hypermodern/ui-theme
               hypermodern/ui-density
               hypermodern/ui-signal
               hypermodern/ui-glow-level
               hypermodern/ui-glow-halo
               hypermodern/ui-enable-pulse
               hypermodern/ui-pulse-commands
               hypermodern/ui-cursor-style
               hypermodern/ui-font-preset
               hypermodern/ui-font-size
               hypermodern/ui-variable-font-size
               hypermodern/ui-padding
               hypermodern/ui-alpha
               hypermodern/ui-enable-transparency
               hypermodern/ui-enable-ligatures
               hypermodern/ui-enable-dim
               hypermodern/ui-enable-solaire
               hypermodern/ui-enable-writing-mode))
    (when (boundp v)
      (customize-save-variable v (symbol-value v))))
  (message "[hypermodern-ui] saved to %s" (or custom-file "~/.emacs.d/custom.el")))

;; ----------------------------
;; Menu (transient if available, fallback if not)
;; ----------------------------

(defun hypermodern/ui-menu ()
  "UI control room. Uses transient if available." 
  (interactive)
  (if (require 'transient nil 'noerror)
      (call-interactively 'hypermodern/ui--transient)
    (message "transient not installed; use M-x hypermodern/ui-style or M-x hypermodern/ui-theme")))

(with-eval-after-load 'transient
  (transient-define-prefix hypermodern/ui--transient ()
    [["Style"
      ("s" "Style preset" hypermodern/ui-style)
      ("t" "Theme"        hypermodern/ui-theme)
      ("d" "Density"      hypermodern/ui-density)
      ("g" "Signal"       hypermodern/ui-signal)
      ("f" "Font"         hypermodern/ui-font)
      ("G" "Glow"         hypermodern/ui-glow)
      ("c" "Cycle glow"   hypermodern/ui-toggle-glow)]
     ["Toggles"
      ("T" "Transparency" hypermodern/ui-toggle-transparency)
      ("P" "Pulse"        hypermodern/ui-toggle-pulse)
      ("W" "Writing mode" hypermodern/ui-toggle-writing)
      ("D" "Dim inactive" hypermodern/ui-toggle-dim)
      ("S" "Solaire"      hypermodern/ui-toggle-solaire)
      ("L" "Ligatures"    hypermodern/ui-toggle-ligatures)]
     ["Persist"
      ("a" "Apply now"    hypermodern/ui-apply)
      ("x" "Save"         hypermodern/ui-save)]]))

(provide 'hypermodern-ui)
;;; hypermodern-ui.el ends here
