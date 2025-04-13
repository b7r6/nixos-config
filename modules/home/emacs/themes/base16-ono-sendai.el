(deftheme base16-ono-sendai
  "Base16 theme: Ono-Sendai Vibrant Accent Variant (de-duplicated).

	Base16 Palette Meanings:
	- base00: Default Background
	- base01: Lighter Background / Selection
	- base02: Active line highlight / subtle contrast
	- base03: Comments & Invisibles
	- base04: Dark Foreground (secondary text)
	- base05: Default Foreground (primary text)
	- base06: Light Foreground (e.g. status text)
	- base07: Bright Foreground (UI elements)
	- base08: Variables / Errors
	- base09: Numbers / Constants (alternate)
	- base0A: Classes / Types
	- base0B: Strings
	- base0C: Functions / Methods
	- base0D: Keywords / Operators
	- base0E: Constants / Accents
	- base0F: Deprecated / Special accents
	")

(let ((base00 "#0F1216") ; Background
      (base01 "#171C22") ; Lighter Background / Selection
      (base02 "#171C22") ; Active line highlight
      (base03 "#171C22") ; Comments & Invisibles
      (base04 "#171C22") ; Dark Foreground
      (base05 "#8b949e") ; Default Foreground
      (base06 "#e6edf3") ; Light Foreground
      (base07 "#f5faff") ; Bright Foreground
      (base08 "#ff5c57") ; Variables / Errors
      (base09 "#ffa657") ; Numbers / Constants (alternate)
      (base0A "#ffa657") ; Classes / Types
      (base0B "#8ddb8c") ; Strings (a greenish hue for contrast)
      (base0C "#58a6ff") ; Functions / Methods
      (base0D "#66baff") ; Keywords / Operators
      (base0E "#b0d8ff") ; Constants / Accents
      (base0F "#c5a0e0")) ; Deprecated / Special accents

  (custom-theme-set-faces
   'base16-ono-sendai
   ;; Default text: primary content using base05 over base00.

   `(default ((t (:foreground ,base05 :background ,base00))))
   ;; Comments: typically shown in a muted color (base03).

   `(font-lock-comment-face ((t (:foreground ,base0F))))
   ;; Strings: given a distinct greenish hue (base0B).

   `(font-lock-doc-face ((t (:foreground ,base0F))))
   ;; Doc comments: often a slightly different shade to differentiate documentation

   `(font-lock-string-face ((t (:foreground ,base0C))))
   ;; Keywords: use a vivid blue (base0D) for operators and keywords.

   `(font-lock-keyword-face ((t (:foreground ,base0D))))
   ;; Function names: use base0C to highlight functions or methods.

   `(font-lock-function-name-face ((t (:foreground ,base0C))))
   ;; Variables: assign base08 to variables and error-prone items.

   `(font-lock-variable-name-face ((t (:foreground ,base08))))
   ;; Types and classes: set in a warm yellow (base0A).

   `(font-lock-type-face ((t (:foreground ,base0A))))
   ;; Constants: use a lighter blue (base0E) to mark constants.

   `(font-lock-constant-face ((t (:foreground ,base0E))))
   ;; Builtins: assign an alternate color (base09) to built-in functions.

   `(font-lock-builtin-face ((t (:foreground ,base09))))
   ;; Warnings: highlight with base08 and bold for emphasis.

   `(font-lock-warning-face ((t (:foreground ,base08 :weight bold))))
   ;; Region: use a slightly lighter background for selections.

   `(region ((t (:background ,base01))))
   ;; Mode-line: status bar styling with contrasting foreground/background.

   `(mode-line ((t (:foreground ,base06 :background ,base04 :box nil))))
   `(mode-line-inactive ((t (:foreground ,base04 :background ,base02 :box nil))))
   ))

(provide-theme 'base16-ono-sendai)
