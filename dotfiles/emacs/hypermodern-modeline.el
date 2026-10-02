;;; hypermodern-modeline.el --- svg modeline from the computed palette -*- lexical-binding: t; -*-

;; ───────────────────────────────────────────────────────────────────
;;                  // modeline // svg // register-aware // 211° //
;; ───────────────────────────────────────────────────────────────────
;;
;; The modeline as part of the theme SYSTEM, not a package with opinions:
;; every pixel is drawn from `hypermodern/compute-current' (the live
;; wintermute 4-vector), so there is no face left uncovered — the theme
;; hole doom-modeline carried (nine themed faces of its forty) closes by
;; construction.
;;
;; Segments are square SVG tags (core svg.el, zero dependencies) wearing
;; the register: at the facility pole they go UPPERCASE with corner
;; bracket caps and a GEN readout; at the affluent pole, soft lowercase.
;; Terminal frames get a faithful text fallback — nix pre-loads, nothing
;; breaks without it.
;;
;; Refresh rides `hypermodern/theme-changed-hook' (run by the palette
;; layer after every `ono-sendai-sync'), so the modeline morphs live with
;; the desktop.

;;; Code:

(require 'svg nil t)

(defvar hypermodern/hero)
(defvar hypermodern/polarity)
(defvar hypermodern/register 1000
  "Live register (per-mille), parsed from wintermute state by the palette layer.")
(defvar hypermodern/wintermute-generation 0
  "Last synced wintermute generation, when known.")

(declare-function hypermodern/compute-current nil)

(defvar hypermodern/modeline-height 22
  "Pixel height of the svg modeline tags (driven by the ui density).")

(defvar hypermodern/modeline--cache (make-hash-table :test 'equal)
  "Bounded rendered segment cache; also cleared on every theme change.")

(defconst hypermodern/modeline-cache-limit 256
  "Maximum number of retained SVG tags, including changing cursor positions.")

(defun hypermodern/modeline--facility-p ()
  "Non-nil when the live register sits at the facility side."
  (>= hypermodern/register 500))

(defun hypermodern/modeline--palette ()
  "The live computed palette, or nil when the palette layer is absent."
  (when (fboundp 'hypermodern/compute-current)
    (hypermodern/compute-current)))

(defun hypermodern/modeline--pget (palette key fallback)
  "KEY from PALETTE with FALLBACK."
  (or (and palette (plist-get palette key)) fallback))

(defun hypermodern/modeline--text-width (text)
  "Pixel width of TEXT in the modeline font."
  (if (fboundp 'string-pixel-width)
      (string-pixel-width text)
    (* (length text) (frame-char-width))))

(defun hypermodern/modeline--tag (text kind)
  "Render TEXT as a square svg tag of KIND (`primary', `plain' or `ghost').
Falls back to propertized text on non-graphic frames."
  (let* ((palette (hypermodern/modeline--palette))
         (facility (hypermodern/modeline--facility-p))
         (text (if facility (upcase text) (downcase text)))
         (bg (hypermodern/modeline--pget palette :base01 "#1e2329"))
         (fg (pcase kind
               ('primary (hypermodern/modeline--pget palette :base0A "#52a5ff"))
               ('ghost (hypermodern/modeline--pget palette :base03 "#3d4752"))
               (_ (hypermodern/modeline--pget palette :base05 "#c1cedc"))))
         (accent (hypermodern/modeline--pget palette :base0A "#52a5ff"))
         (key (list text kind fg bg accent facility hypermodern/modeline-height
                    (frame-char-width))))
    (if (not (and (featurep 'svg) (display-graphic-p)))
        (propertize (format " %s " text) 'face (list :foreground fg :background bg))
      (or (gethash key hypermodern/modeline--cache)
          (let* ((h hypermodern/modeline-height)
                 (pad 8)
                 (tw (hypermodern/modeline--text-width text))
                 (w (+ tw (* 2 pad)))
                 (image (svg-create w h)))
            (svg-rectangle image 0 0 w h :fill bg)
            (svg-text image text
                      :x pad :y (- h 7)
                      :fill fg
                      :font-family "Berkeley Mono"
                      :font-size (- h 9)
                      :letter-spacing (if facility "1.2" "0"))
            ;; facility: corner bracket caps, the geo-hover mark
            (when facility
              (let ((s accent) (a 4))
                (svg-line image 0 0 a 0 :stroke s) (svg-line image 0 0 0 a :stroke s)
                (svg-line image w 0 (- w a) 0 :stroke s) (svg-line image w 0 w a :stroke s)
                (svg-line image 0 h a h :stroke s) (svg-line image 0 h 0 (- h a) :stroke s)
                (svg-line image w h (- w a) h :stroke s) (svg-line image w h w (- h a) :stroke s)))
            ;; Cursor positions and buffer names have unbounded cardinality.
            ;; Retain a small working set rather than every position visited
            ;; during a days-long session. Common tags are rebuilt on demand.
            (when (>= (hash-table-count hypermodern/modeline--cache)
                      hypermodern/modeline-cache-limit)
              (clrhash hypermodern/modeline--cache))
            (puthash key
                     (propertize (format " %s " text)
                                 'display (svg-image image :ascent 'center))
                     hypermodern/modeline--cache))))))

(defun hypermodern/modeline--vc ()
  "Current branch name, or nil."
  (when (and vc-mode buffer-file-name)
    (replace-regexp-in-string "^ Git[:-]" "" (substring-no-properties vc-mode))))

(defun hypermodern/modeline--render-left ()
  "Left segment group."
  (let ((mod (and (buffer-modified-p) (buffer-file-name))))
    (concat
     (hypermodern/modeline--tag (if (hypermodern/modeline--facility-p) "▞" "◦") 'primary)
     (hypermodern/modeline--tag
      (concat (buffer-name) (if mod " ●" "")) (if mod 'primary 'plain))
     (hypermodern/modeline--tag (format-mode-line mode-name) 'ghost))))

(defun hypermodern/modeline--render-right ()
  "Right segment group."
  (concat
   (when-let* ((branch (hypermodern/modeline--vc)))
     (hypermodern/modeline--tag branch 'ghost))
   (hypermodern/modeline--tag (format-mode-line "%l:%c") 'plain)
   (when (hypermodern/modeline--facility-p)
     (hypermodern/modeline--tag
      (format "gen %s" hypermodern/wintermute-generation) 'ghost))))

(defun hypermodern/modeline--apply-faces ()
  "Close the theme hole: base modeline faces from the live palette."
  (let* ((palette (hypermodern/modeline--palette))
         (bg (hypermodern/modeline--pget palette :base00 "#191c1f"))
         (bg-alt (hypermodern/modeline--pget palette :base01 "#1e2329"))
         (fg (hypermodern/modeline--pget palette :base04 "#6c7a89")))
    (dolist (face '(mode-line mode-line-active))
      (when (facep face)
        (set-face-attribute face nil :background bg-alt :foreground fg :box nil)))
    (when (facep 'mode-line-inactive)
      (set-face-attribute 'mode-line-inactive nil
                          :background bg :foreground fg :box nil))))

(defun hypermodern/modeline-refresh ()
  "Re-theme and redraw the modeline (theme-change hook target)."
  (clrhash hypermodern/modeline--cache)
  (hypermodern/modeline--apply-faces)
  (force-mode-line-update t))

(defun hypermodern/modeline-enable ()
  "Install the svg modeline as the default `mode-line-format'."
  (setq-default mode-line-format
                '((:eval (hypermodern/modeline--render-left))
                  mode-line-format-right-align
                  (:eval (hypermodern/modeline--render-right))
                  " "))
  (hypermodern/modeline-refresh)
  (add-hook 'hypermodern/theme-changed-hook #'hypermodern/modeline-refresh))

(provide 'hypermodern-modeline)
;;; hypermodern-modeline.el ends here
