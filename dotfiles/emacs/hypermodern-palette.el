;;; hypermodern-palette.el --- computed ono-sendai/maas palettes -*- lexical-binding: t; -*-

;; ───────────────────────────────────────────────────────────────────
;;                     // theme engine // computed palettes // 211° //
;; ───────────────────────────────────────────────────────────────────
;;
;; The FOURTH implementation of the ono-sendai palette math (Lean
;; generator, lib.nix, wintermute, and now elisp) — pinned to the same
;; 66 conformance vectors by checks.ono-sendai-parity, which runs this
;; file under `emacs --batch'.  Integer HSL→RGB, fixed-point ×1000,
;; round-half-up: any drift from the Lean reference is a CI failure.
;;
;; Zero dependencies, loadable standalone.  When loaded under the full
;; init.el it plugs into `hypermodern/generate-faces' and gives:
;;
;;   ono-sendai-set-hero / -set-axis / -set-level / -set-polarity
;;   ono-sendai-sync   — read wintermute's theme.state and apply; this
;;                       is the daemon's whole emacs live channel
;;
;; Works identically in terminal (-nw) and pgtk frames: faces carry
;; explicit hex, no terminal-palette dependence.

;;; Code:

;; ── integer HSL → RGB (exact port of the Lean reference) ───────────

(defun hypermodern/hsl--channel (base m1000)
  (min 255 (/ (+ (* (+ base m1000) 255) 500) 1000)))

(defun hypermodern/hsl-to-hex (h s l)
  "Hex color at hue H (any integer), S and L clamped to [0, 100]."
  (let* ((h (mod h 360))
         (s (min s 100))
         (l (min l 100))
         (s1000 (* s 10))
         (l1000 (* l 10))
         (two-l (* 2 l1000))
         (diff (abs (- two-l 1000)))
         (c1000 (/ (* (- 1000 diff) s1000) 1000))
         (sector (/ h 60))
         (pair (mod h 120))
         (abs-val (abs (- pair 60)))
         (x1000 (/ (* c1000 (- 60 abs-val)) 60))
         (m1000 (- l1000 (/ c1000 2)))
         (rgb (pcase sector
                (0 (list c1000 x1000 0))
                (1 (list x1000 c1000 0))
                (2 (list 0 c1000 x1000))
                (3 (list 0 x1000 c1000))
                (4 (list x1000 0 c1000))
                (_ (list c1000 0 x1000)))))
    (format "#%02x%02x%02x"
            (hypermodern/hsl--channel (nth 0 rgb) m1000)
            (hypermodern/hsl--channel (nth 1 rgb) m1000)
            (hypermodern/hsl--channel (nth 2 rgb) m1000))))

;; ── the slot tables ────────────────────────────────────────────────

(defconst hypermodern/black-levels
  '((void . 0) (deep . 4) (night . 8) (carbon . 11) (github . 16)))

(defconst hypermodern/white-levels
  '((tessier . 100) (neoform . 97) (ghost . 92)))

(defun hypermodern/compute-dark (level &optional hero axis)
  "Ono-sendai palette at black LEVEL; ramp hue-locked to 211."
  (let ((L (alist-get level hypermodern/black-levels 11))
        (hero (or hero 211))
        (axis (or axis 201)))
    (list :name (format "Ono-Sendai %s" (capitalize (symbol-name level)))
          :variant 'dark
          :base00 (hypermodern/hsl-to-hex 211 12 (+ L 0))
          :base01 (hypermodern/hsl-to-hex 211 16 (+ L 3))
          :base02 (hypermodern/hsl-to-hex 211 17 (+ L 8))
          :base03 (hypermodern/hsl-to-hex 211 15 (+ L 17))
          :base04 (hypermodern/hsl-to-hex 211 12 48)
          :base05 (hypermodern/hsl-to-hex 211 28 81)
          :base06 (hypermodern/hsl-to-hex 211 32 89)
          :base07 (hypermodern/hsl-to-hex 211 36 95)
          :base08 (hypermodern/hsl-to-hex axis 100 86)
          :base09 (hypermodern/hsl-to-hex axis 100 75)
          :base0A (hypermodern/hsl-to-hex hero 100 66)
          :base0B (hypermodern/hsl-to-hex hero 100 57)
          :base0C (hypermodern/hsl-to-hex hero 94 45)
          :base0D (hypermodern/hsl-to-hex hero 100 65)
          :base0E (hypermodern/hsl-to-hex hero 100 71)
          :base0F (hypermodern/hsl-to-hex hero 86 53))))

(defun hypermodern/compute-light (level &optional hero axis ramp)
  "Maas palette at white LEVEL; RAMP unlocks the paper tint (bioptic = 36)."
  (let ((W (alist-get level hypermodern/white-levels 97))
        (hero (or hero 211))
        (axis (or axis 201))
        (ramp (or ramp 211)))
    (list :name (format "Maas %s" (capitalize (symbol-name level)))
          :variant 'light
          :base00 (hypermodern/hsl-to-hex ramp 33 (- W 0))
          :base01 (hypermodern/hsl-to-hex ramp 28 (- W 4))
          :base02 (hypermodern/hsl-to-hex ramp 26 (- W 10))
          :base03 (hypermodern/hsl-to-hex ramp 15 60)
          :base04 (hypermodern/hsl-to-hex ramp 15 43)
          :base05 (hypermodern/hsl-to-hex ramp 23 23)
          :base06 (hypermodern/hsl-to-hex ramp 25 15)
          :base07 (hypermodern/hsl-to-hex ramp 28 8)
          :base08 (hypermodern/hsl-to-hex axis 90 40)
          :base09 (hypermodern/hsl-to-hex axis 100 34)
          :base0A (hypermodern/hsl-to-hex hero 94 45)
          :base0B (hypermodern/hsl-to-hex hero 100 40)
          :base0C (hypermodern/hsl-to-hex hero 100 34)
          :base0D (hypermodern/hsl-to-hex hero 86 47)
          :base0E (hypermodern/hsl-to-hex hero 100 50)
          :base0F (hypermodern/hsl-to-hex hero 86 38))))

;; ── live vector state ──────────────────────────────────────────────

(defvar hypermodern/hero 211)
(defvar hypermodern/axis 201)
(defvar hypermodern/polarity 'dark)
(defvar hypermodern/level 'carbon)
(defvar hypermodern/ramp 211)
(defvar hypermodern/register 1000
  "Register axis position (per-mille), affluent 0 ... facility 1000.")
(defvar hypermodern/wintermute-generation 0
  "Generation of the last synced wintermute state.")

(defvar hypermodern/theme-changed-hook nil
  "Run after the computed theme is (re)applied; modeline etc. subscribe.")

(defun hypermodern/compute-current ()
  (if (eq hypermodern/polarity 'light)
      (hypermodern/compute-light hypermodern/level hypermodern/hero
                                 hypermodern/axis hypermodern/ramp)
    (hypermodern/compute-dark hypermodern/level hypermodern/hero
                              hypermodern/axis)))

(defun hypermodern/apply-computed ()
  "Recompute the palette from the live vector and apply it.
Uses the init.el face engine when present; no-op under --batch."
  (when (fboundp 'hypermodern/generate-faces)
    (let* ((palette (hypermodern/compute-current))
           (faces (hypermodern/generate-faces palette)))
      (mapc #'disable-theme custom-enabled-themes)
      (dolist (face-spec faces)
        (face-spec-set (car face-spec) (cadr face-spec) 'face-defface-spec))
      (let ((bg (plist-get palette :base00)))
        (modify-all-frames-parameters `((background-color . ,bg))))
      (run-hooks 'hypermodern/theme-changed-hook)
      (message "// theme // %s // hero %d axis %d //"
               (plist-get palette :name) hypermodern/hero hypermodern/axis))))

;; ── the knobs (wintermute's emacsclient endpoints) ─────────────────

(defun ono-sendai-set-hero (hue)
  "Set the hero accent HUE (base0A–0F) and reapply."
  (interactive "nHero hue (0-359): ")
  (setq hypermodern/hero (mod hue 360))
  (hypermodern/apply-computed))

(defun ono-sendai-set-axis (hue)
  "Set the axis accent HUE (base08–09) and reapply."
  (interactive "nAxis hue (0-359): ")
  (setq hypermodern/axis (mod hue 360))
  (hypermodern/apply-computed))

(defun ono-sendai-set-level (level)
  "Set the luminance LEVEL (symbol) and matching polarity, then reapply."
  (interactive
   (list (intern (completing-read
                  "Level: "
                  (mapcar (lambda (c) (symbol-name (car c)))
                          (append hypermodern/black-levels hypermodern/white-levels))
                  nil t))))
  (setq hypermodern/level level
        hypermodern/polarity
        (if (assq level hypermodern/white-levels) 'light 'dark))
  (hypermodern/apply-computed))

(defun ono-sendai-set-polarity (polarity)
  "Flip day/night: POLARITY is `dark' or `light' (default level per side)."
  (interactive (list (intern (completing-read "Polarity: " '("dark" "light") nil t))))
  (setq hypermodern/polarity polarity
        hypermodern/level (if (eq polarity 'light) 'neoform 'carbon))
  (hypermodern/apply-computed))

;; ── wintermute sync — the whole live channel in one command ────────

(defun hypermodern/wintermute-state-file ()
  (expand-file-name
   "wintermute/theme.state"
   (or (getenv "XDG_STATE_HOME")
       (expand-file-name "~/.local/state"))))

(defun ono-sendai-sync ()
  "Read wintermute's theme.state and apply the 4-vector.
Unknown keys are ignored; a missing file is a silent no-op — the
config never depends on the daemon, it only listens to it."
  (interactive)
  (let ((state (hypermodern/wintermute-state-file)))
    (when (file-readable-p state)
      (with-temp-buffer
        (insert-file-contents state)
        (dolist (line (split-string (buffer-string) "\n" t))
          (pcase (split-string line)
            (`("hero" ,v) (setq hypermodern/hero (mod (string-to-number v) 360)))
            (`("axis" ,v) (setq hypermodern/axis (mod (string-to-number v) 360)))
            (`("ramp" ,v) (setq hypermodern/ramp (mod (string-to-number v) 360)))
            (`("register" ,v) (setq hypermodern/register (string-to-number v)))
            (`("generation" ,v) (setq hypermodern/wintermute-generation (string-to-number v)))
            (`("polarity" ,v) (setq hypermodern/polarity (intern v)))
            (`("level" ,v)
             (let ((sym (intern v)))
               (when (or (assq sym hypermodern/black-levels)
                         (assq sym hypermodern/white-levels))
                 (setq hypermodern/level sym))))
            (_ nil))))
      (hypermodern/apply-computed))))

;; ── conformance vectors (CI: emacs --batch) ────────────────────────

(defconst hypermodern/vector-hues
  '((211 . 201) (36 . 26) (0 . 350) (120 . 110) (262 . 252) (300 . 290)))

(defun hypermodern/vector-json (slug hero axis ramp palette)
  (concat
   (format "{\"slug\": \"%s\", \"heroHue\": %d, \"axisHue\": %d, \"rampHue\": %d"
           slug hero axis ramp)
   (mapconcat
    (lambda (slot)
      (format ", \"%s\": \"%s\""
              (substring (symbol-name slot) 1)
              (plist-get palette slot)))
    '(:base00 :base01 :base02 :base03 :base04 :base05 :base06 :base07
      :base08 :base09 :base0A :base0B :base0C :base0D :base0E :base0F)
    "")
   "}"))

(defun hypermodern/emit-vectors ()
  "Print the 66 conformance vectors as JSON (order matches the Lean reference)."
  (let (vectors)
    (dolist (hu hypermodern/vector-hues)
      (dolist (level (mapcar #'car hypermodern/black-levels))
        (push (hypermodern/vector-json
               (format "ono-sendai-%s" level) (car hu) (cdr hu) 211
               (hypermodern/compute-dark level (car hu) (cdr hu)))
              vectors)))
    (dolist (hu hypermodern/vector-hues)
      (dolist (level (mapcar #'car hypermodern/white-levels))
        (dolist (ramp '(211 36))
          (push (hypermodern/vector-json
                 (format "maas-%s" level) (car hu) (cdr hu) ramp
                 (hypermodern/compute-light level (car hu) (cdr hu) ramp))
                vectors))))
    (princ (concat "[\n  " (mapconcat #'identity (nreverse vectors) ",\n  ") "\n]\n"))))

;; ── startup: follow wintermute if it's there ───────────────────────

(when (and (not noninteractive) (fboundp 'hypermodern/generate-faces))
  (ono-sendai-sync))

(provide 'hypermodern-palette)
;;; hypermodern-palette.el ends here
