import OnoSendaiGen.IO

/-!
# Ono-Sendai Base16 — Editor Plugin Generator

Generates three complete editor plugins from a single palette definition:

1. **Emacs** — `ono-sendai-theme.el` with `M-x ono-sendai-set-hero` / `M-x ono-sendai-set-axis`
2. **Neovim** — Lua plugin with `:OnoSendaiHero` / `:OnoSendaiAxis` / Telescope picker
3. **VSCode** — Extension with `package.json`, theme JSON, and keybindings

All three enforce the 211° hue-lock rule:
  - Grayscale ramp is always 211°, only lightness varies with black level
  - Hero hue controls base0A–base0F (classes, strings, support, functions, keywords)
  - Axis hue controls base08–base09 (variables, integers — the cool shift)

## Usage

    lake env lean --run OnoSendaiGen.lean
    # produces:
    #   out/emacs/ono-sendai-theme.el
    #   out/nvim/lua/ono-sendai/init.lua
    #   out/nvim/lua/ono-sendai/palette.lua
    #   out/nvim/plugin/ono-sendai.lua
    #   out/vscode/package.json
    #   out/vscode/themes/ono-sendai-color-theme.json
-/

-- ============================================================
-- §1  Bounded primitives (same as before)
-- ============================================================

abbrev Channel := Fin 256
abbrev Hue     := Fin 360
abbrev Pct     := Fin 101

structure RGB where
  r : Channel
  g : Channel
  b : Channel
  deriving Repr, BEq

structure HSL where
  h : Hue
  s : Pct
  l : Pct
  deriving Repr, BEq

-- ============================================================
-- §2  Color math
-- ============================================================

private def hexDigit (n : Fin 16) : Char :=
  if n.val < 10 then Char.ofNat (n.val + 48)
  else Char.ofNat (n.val + 87)

def Channel.toHex (c : Channel) : String :=
  let hi : Fin 16 := ⟨c.val / 16, by omega⟩
  let lo : Fin 16 := ⟨c.val % 16, by omega⟩
  s!"{hexDigit hi}{hexDigit lo}"

def RGB.toHex (c : RGB) : String :=
  s!"#{c.r.toHex}{c.g.toHex}{c.b.toHex}"

def HSL.toRGB (c : HSL) : RGB :=
  let s1000 : Nat := c.s.val * 10
  let l1000 : Nat := c.l.val * 10
  let twoL := 2 * l1000
  let diff := if twoL ≥ 1000 then twoL - 1000 else 1000 - twoL
  let c1000 := ((1000 - diff) * s1000) / 1000
  let hmod := c.h.val % 360
  let sector := hmod / 60
  let pair := hmod % 120
  let absVal := if pair ≥ 60 then pair - 60 else 60 - pair
  let x1000 := (c1000 * (60 - absVal)) / 60
  let m1000 := l1000 - c1000 / 2
  let (r', g', b') := match sector with
    | 0 => (c1000, x1000, 0) | 1 => (x1000, c1000, 0)
    | 2 => (0, c1000, x1000) | 3 => (0, x1000, c1000)
    | 4 => (x1000, 0, c1000) | _ => (c1000, 0, x1000)
  let clamp (v : Int) : Channel :=
    let n := v.toNat
    if h : n < 256 then ⟨n, h⟩ else ⟨255, by omega⟩
  let ch (base : Nat) : Channel :=
    clamp (((base + m1000) * 255 + 500) / 1000 : Int)
  { r := ch r', g := ch g', b := ch b' }

def normalizeHue (n : Int) : Hue :=
  let m := ((n % 360 + 360) % 360).toNat
  if h : m < 360 then ⟨m, h⟩ else ⟨0, by omega⟩

-- ============================================================
-- §3  Palette
-- ============================================================

inductive BlackLevel where
  | void | deep | night | carbon | github
  deriving Repr, BEq

def BlackLevel.baseL : BlackLevel → Nat
  | .void => 0 | .deep => 4 | .night => 8 | .carbon => 11 | .github => 16

def BlackLevel.name : BlackLevel → String
  | .void => "void" | .deep => "deep" | .night => "night"
  | .carbon => "carbon" | .github => "github"

/-- White levels for the maas (light) polarity — the mirror of `BlackLevel`.
    `tessier` is clinical pure white, `neoform` the default near-white,
    `ghost` a fog that sits where `github` sits on the dark side. -/
inductive WhiteLevel where
  | tessier | neoform | ghost
  deriving Repr, BEq

def WhiteLevel.baseL : WhiteLevel → Nat
  | .tessier => 100 | .neoform => 97 | .ghost => 92

def WhiteLevel.name : WhiteLevel → String
  | .tessier => "tessier" | .neoform => "neoform" | .ghost => "ghost"

structure Palette where
  base00 : String  -- hex strings for simplicity in codegen
  base01 : String
  base02 : String
  base03 : String
  base04 : String
  base05 : String
  base06 : String
  base07 : String
  base08 : String
  base09 : String
  base0A : String
  base0B : String
  base0C : String
  base0D : String
  base0E : String
  base0F : String
  deriving Repr

/-- The manufacturer axis (mirror of the wintermute daemon's type): each
    family is a night/day pair — straylight = ono-sendai/maas at 211°,
    hosaka = blackwell/grace at 165° phosphor. The night ramp hue is
    family-owned; the lock stays the absence of a call-site parameter. -/
inductive PaletteFamily where
  | straylight
  | hosaka
  deriving Repr, BEq, DecidableEq

def PaletteFamily.darkRampHue : PaletteFamily → Nat
  | .straylight => 211
  | .hosaka => 165

private def hsl211 (s l : Nat) : String :=
  (HSL.mk ⟨211, by omega⟩
    (if hs : s ≤ 100 then ⟨s, by omega⟩ else ⟨100, by omega⟩)
    (if hl : l ≤ 100 then ⟨l, by omega⟩ else ⟨100, by omega⟩)).toRGB.toHex

private def hslAt (h s l : Nat) : String :=
  (HSL.mk (normalizeHue h)
    (if hs : s ≤ 100 then ⟨s, by omega⟩ else ⟨100, by omega⟩)
    (if hl : l ≤ 100 then ⟨l, by omega⟩ else ⟨100, by omega⟩)).toRGB.toHex

def makePalette (family : PaletteFamily) (level : BlackLevel)
    (heroHue : Nat := 211) (axisHue : Nat := 201) : Palette :=
  let L := level.baseL
  let R := family.darkRampHue
  { base00 := hslAt R 12 (L + 0)
  , base01 := hslAt R 16 (L + 3)
  , base02 := hslAt R 17 (L + 8)
  , base03 := hslAt R 15 (L + 17)
  , base04 := hslAt R 12 48
  , base05 := hslAt R 28 81
  , base06 := hslAt R 32 89
  , base07 := hslAt R 36 95
  , base08 := hslAt axisHue 100 86
  , base09 := hslAt axisHue 100 75
  , base0A := hslAt heroHue 100 66
  , base0B := hslAt heroHue 100 57
  , base0C := hslAt heroHue  94 45
  , base0D := hslAt heroHue 100 65
  , base0E := hslAt heroHue 100 71
  , base0F := hslAt heroHue  86 53
  }

/-- The maas (light) polarity. Ramp descends from the white level; saturation
    rises toward both ends of the ramp the way the dark side's does, so paper
    stays cool instead of going gray. Accents are the same hue family as the
    dark palette but cut deep for light ground — maas `base0A` at the default
    hero is the dark side's `base0C` (`#0969da`), which is exactly the value
    the brand site ships as maas primary.

    `rampHue` unlocks the paper tint for warm variants (bioptic = 36°) while
    hero/axis stay wherever the theme puts them. Defaults keep the 211° lock. -/
def makePaletteLight (level : WhiteLevel) (heroHue : Nat := 211) (axisHue : Nat := 201)
    (rampHue : Nat := 211) : Palette :=
  let W := level.baseL
  let ramp (s l : Nat) : String := hslAt rampHue s l
  { base00 := ramp 33 (W - 0)
  , base01 := ramp 28 (W - 4)
  , base02 := ramp 26 (W - 10)
  , base03 := ramp 15 60
  , base04 := ramp 15 43
  , base05 := ramp 23 23
  , base06 := ramp 25 15
  , base07 := ramp 28 8
  , base08 := hslAt axisHue  90 40
  , base09 := hslAt axisHue 100 34
  , base0A := hslAt heroHue  94 45
  , base0B := hslAt heroHue 100 40
  , base0C := hslAt heroHue 100 34
  , base0D := hslAt heroHue  86 47
  , base0E := hslAt heroHue 100 50
  , base0F := hslAt heroHue  86 38
  }

def Palette.slots (p : Palette) : Array (String × String) :=
  #[("base00", p.base00), ("base01", p.base01), ("base02", p.base02), ("base03", p.base03),
    ("base04", p.base04), ("base05", p.base05), ("base06", p.base06), ("base07", p.base07),
    ("base08", p.base08), ("base09", p.base09), ("base0A", p.base0A), ("base0B", p.base0B),
    ("base0C", p.base0C), ("base0D", p.base0D), ("base0E", p.base0E), ("base0F", p.base0F)]

-- ============================================================
-- §4a  JSON output for Nix consumption
-- ============================================================

private def familyDisplay : String → String
  | "ono-sendai" => "Ono-Sendai"
  | "maas" => "Maas"
  | s => s.capitalize

def Palette.toJsonWith (p : Palette) (family levelName variant : String)
    (heroHue axisHue rampHue : Nat) : String :=
  let slots := p.slots.toList.map fun (name, hex) => s!"  \"{name}\": \"{hex}\""
  let header := [
    s!"  \"slug\": \"{family}-{levelName}\"",
    s!"  \"name\": \"{familyDisplay family} {levelName.capitalize}\"",
    s!"  \"author\": \"b7r6\"",
    s!"  \"variant\": \"{variant}\"",
    s!"  \"heroHue\": {heroHue}",
    s!"  \"axisHue\": {axisHue}",
    s!"  \"rampHue\": {rampHue}",
    s!"  \"level\": \"{levelName}\""
  ]
  "{\n" ++ String.intercalate ",\n" (header ++ slots) ++ "\n}"

def Palette.toJson (p : Palette) (level : BlackLevel) (heroHue axisHue : Nat) : String :=
  p.toJsonWith "ono-sendai" level.name "dark" heroHue axisHue 211

def generateJson (level : BlackLevel) (heroHue : Nat := 211) (axisHue : Nat := 201) : String :=
  let p := makePalette .straylight level heroHue axisHue
  p.toJson level heroHue axisHue

def generateJsonLight (level : WhiteLevel) (heroHue : Nat := 211) (axisHue : Nat := 201)
    (rampHue : Nat := 211) : String :=
  let p := makePaletteLight level heroHue axisHue rampHue
  p.toJsonWith "maas" level.name "light" heroHue axisHue rampHue

def allBlackLevels : List BlackLevel := [.void, .deep, .night, .carbon, .github]
def allWhiteLevels : List WhiteLevel := [.tessier, .neoform, .ghost]

def generateAllLevelsJson (heroHue : Nat := 211) (axisHue : Nat := 201) : String :=
  let darks := allBlackLevels.map fun level =>
    let p := makePalette .straylight level heroHue axisHue
    s!"  \"ono-sendai-{level.name}\": {p.toJson level heroHue axisHue}"
  let lights := allWhiteLevels.map fun level =>
    let p := makePaletteLight level heroHue axisHue
    s!"  \"maas-{level.name}\": {p.toJsonWith "maas" level.name "light" heroHue axisHue 211}"
  "{\n" ++ String.intercalate ",\n" (darks ++ lights) ++ "\n}"

-- ============================================================
-- §4b  Conformance vectors
-- ============================================================

/-- Golden vectors pinning the integer color math. Every reimplementation of
    the palette derivation (Nix, QML, GLSL, elisp, Lua, wintermute) is tested
    against this file — the Lean definitions are the truth, everything else
    is verified plumbing. Hue spread covers the lock (211/201), the warm
    paper override (36), and the degenerate/extreme sectors. -/
def generateVectors : String :=
  let hues : List (Nat × Nat) := [(211, 201), (36, 26), (0, 350), (120, 110), (262, 252), (300, 290)]
  let darkVecs := hues.flatMap fun (hero, axis) =>
    allBlackLevels.map fun level =>
      let p := makePalette .straylight level hero axis
      p.toJsonWith "ono-sendai" level.name "dark" hero axis 211
  let lightVecs := hues.flatMap fun (hero, axis) =>
    allWhiteLevels.flatMap fun level =>
      [211, 36].map fun ramp =>
        let p := makePaletteLight level hero axis ramp
        p.toJsonWith "maas" level.name "light" hero axis ramp
  -- hosaka pins the family-ramp path at its signature pair (hero 78 =
  -- #76B900's hue, axis 168 plasma teal); blackwell 165, grace 150
  let hosakaDark := allBlackLevels.map fun level =>
    let p := makePalette .hosaka level 78 168
    p.toJsonWith "hosaka-blackwell" level.name "dark" 78 168 165
  let hosakaLight := allWhiteLevels.map fun level =>
    let p := makePaletteLight level 78 168 150
    p.toJsonWith "hosaka-grace" level.name "light" 78 168 150
  let all := (darkVecs ++ lightVecs ++ hosakaDark ++ hosakaLight).map fun j =>
    -- reindent each palette object to sit inside the array
    String.intercalate "\n  " (j.splitOn "\n")
  "[\n  " ++ String.intercalate ",\n  " all ++ "\n]"

-- ============================================================
-- §4  Emacs generator
-- ============================================================

def generateEmacs (defaultLevel : BlackLevel) (defaultHero defaultAxis : Nat) : String :=
  let p := makePalette .straylight defaultLevel defaultHero defaultAxis
  let colorList := String.intercalate "\n"
    (p.slots.toList.map fun (name, hex) => s!"      ({name} \"{hex}\")")
  -- The elisp template
  s!";;; ono-sendai-theme.el --- 211° Hue-Lock Base16 Theme -*- lexical-binding: t -*-

;; Author: generated by OnoSendaiGen.lean
;; Version: 1.0.0
;; Package-Requires: ((emacs \"27.1\") (base16-theme \"3.0\"))
;; Keywords: faces themes
;; URL: https://github.com/straylight-software/ono-sendai

;;; Commentary:

;; A base16 theme locked to 211° hue backgrounds with two degrees of
;; freedom: hero-hue (base0A-0F) and axis-hue (base08-09).
;;
;; Usage:
;;   (require 'ono-sendai-theme)
;;   (load-theme 'ono-sendai t)
;;
;; Interactive commands:
;;   M-x ono-sendai-set-hero    — change the hero hue (0-359)
;;   M-x ono-sendai-set-axis    — change the axis hue (0-359)
;;   M-x ono-sendai-set-level   — change black level (void/deep/night/carbon/github)
;;   M-x ono-sendai-save        — write current palette to ~/.ono-sendai.el

;;; Code:

(require 'base16-theme)

(defgroup ono-sendai nil
  \"Ono-Sendai 211° hue-locked theme.\"
  :group 'faces)

(defcustom ono-sendai-hero-hue {defaultHero}
  \"Hero accent hue (0-359). Controls base0A through base0F.\"
  :type 'integer
  :group 'ono-sendai)

(defcustom ono-sendai-axis-hue {defaultAxis}
  \"Axis accent hue (0-359). Controls base08 and base09.\"
  :type 'integer
  :group 'ono-sendai)

(defcustom ono-sendai-black-level 'carbon
  \"Black level variant.\"
  :type '(choice (const void) (const deep) (const night) (const carbon) (const github))
  :group 'ono-sendai)

(defcustom ono-sendai-save-file \"~/.ono-sendai.el\"
  \"File to persist palette configuration.\"
  :type 'file
  :group 'ono-sendai)

;;; --- HSL→RGB (integer math, matches the Lean implementation) ---

(defun ono-sendai--hsl-to-rgb (h s l)
  \"Convert HSL (h:0-360 s:0-100 l:0-100) to (R G B) each 0-255.\"
  (let* ((s1000 (* s 10))
         (l1000 (* l 10))
         (two-l (* 2 l1000))
         (diff (abs (- two-l 1000)))
         (c1000 (/ (* (- 1000 diff) s1000) 1000))
         (hmod (mod h 360))
         (sector (/ hmod 60))
         (pair (mod hmod 120))
         (abs-val (abs (- pair 60)))
         (x1000 (/ (* c1000 (- 60 abs-val)) 60))
         (m1000 (- l1000 (/ c1000 2)))
         (rgb (pcase sector
                (0 (list c1000 x1000 0)) (1 (list x1000 c1000 0))
                (2 (list 0 c1000 x1000)) (3 (list 0 x1000 c1000))
                (4 (list x1000 0 c1000)) (_ (list c1000 0 x1000)))))
    (mapcar (lambda (base)
              (min 255 (max 0 (/ (+ (* (+ base m1000) 255) 500) 1000))))
            rgb)))

(defun ono-sendai--rgb-to-hex (r g b)
  \"Format RGB 0-255 to \"#rrggbb\".\"
  (format \"#%02x%02x%02x\" r g b))

(defun ono-sendai--hsl-hex (h s l)
  \"HSL to hex string.\"
  (apply #'ono-sendai--rgb-to-hex (ono-sendai--hsl-to-rgb h s l)))

;;; --- Palette computation ---

(defun ono-sendai--black-level-offset (level)
  \"Return base lightness for LEVEL.\"
  (pcase level
    ('void   0)  ('deep   4)  ('night  8)
    ('carbon 11) ('github 16) (_       11)))

(defun ono-sendai--compute-palette ()
  \"Compute the full base16 palette from current settings.\"
  (let* ((L (ono-sendai--black-level-offset ono-sendai-black-level))
         (hero ono-sendai-hero-hue)
         (axis ono-sendai-axis-hue))
    (list
     :base00 (ono-sendai--hsl-hex 211 12 (+ L 0))
     :base01 (ono-sendai--hsl-hex 211 16 (+ L 3))
     :base02 (ono-sendai--hsl-hex 211 17 (+ L 8))
     :base03 (ono-sendai--hsl-hex 211 15 (+ L 17))
     :base04 (ono-sendai--hsl-hex 211 12 48)
     :base05 (ono-sendai--hsl-hex 211 28 81)
     :base06 (ono-sendai--hsl-hex 211 32 89)
     :base07 (ono-sendai--hsl-hex 211 36 95)
     :base08 (ono-sendai--hsl-hex axis 100 86)
     :base09 (ono-sendai--hsl-hex axis 100 75)
     :base0A (ono-sendai--hsl-hex hero 100 66)
     :base0B (ono-sendai--hsl-hex hero 100 57)
     :base0C (ono-sendai--hsl-hex hero  94 45)
     :base0D (ono-sendai--hsl-hex hero 100 65)
     :base0E (ono-sendai--hsl-hex hero 100 71)
     :base0F (ono-sendai--hsl-hex hero  86 53))))

;;; --- Theme application ---

(defun ono-sendai--apply ()
  \"Recompute and apply the theme.\"
  (let ((colors (ono-sendai--compute-palette)))
    (base16-theme-define 'ono-sendai colors)
    (enable-theme 'ono-sendai)))

;;;###autoload
(defun ono-sendai-set-hero (hue)
  \"Set the hero hue and re-apply theme.\"
  (interactive \"nHero hue (0-359): \")
  (setq ono-sendai-hero-hue (mod hue 360))
  (ono-sendai--apply)
  (message \"Ono-Sendai hero → %d°\" ono-sendai-hero-hue))

;;;###autoload
(defun ono-sendai-set-axis (hue)
  \"Set the axis hue and re-apply theme.\"
  (interactive \"nAxis hue (0-359): \")
  (setq ono-sendai-axis-hue (mod hue 360))
  (ono-sendai--apply)
  (message \"Ono-Sendai axis → %d°\" ono-sendai-axis-hue))

;;;###autoload
(defun ono-sendai-set-level (level)
  \"Set the black level and re-apply theme.\"
  (interactive
   (list (intern (completing-read \"Black level: \"
                   '(\"void\" \"deep\" \"night\" \"carbon\" \"github\")
                   nil t))))
  (setq ono-sendai-black-level level)
  (ono-sendai--apply)
  (message \"Ono-Sendai level → %s\" level))

;;;###autoload
(defun ono-sendai-save ()
  \"Persist current hero/axis/level to `ono-sendai-save-file'.\"
  (interactive)
  (with-temp-file ono-sendai-save-file
    (insert (format \";;; ono-sendai saved palette — %s\\n\" (current-time-string)))
    (insert (format \"(setq ono-sendai-hero-hue %d)\\n\" ono-sendai-hero-hue))
    (insert (format \"(setq ono-sendai-axis-hue %d)\\n\" ono-sendai-axis-hue))
    (insert (format \"(setq ono-sendai-black-level '%s)\\n\" ono-sendai-black-level)))
  (message \"Saved to %s\" ono-sendai-save-file))

;;;###autoload
(defun ono-sendai-load ()
  \"Load saved palette from `ono-sendai-save-file' if it exists.\"
  (interactive)
  (when (file-exists-p ono-sendai-save-file)
    (load ono-sendai-save-file nil t)
    (ono-sendai--apply)
    (message \"Loaded Ono-Sendai palette from %s\" ono-sendai-save-file)))

;; --- Default palette for base16-theme compatibility ---
;; This lets `load-theme 'ono-sendai` work out of the box.

(defvar ono-sendai-theme-colors
  (ono-sendai--compute-palette)
  \"Current Ono-Sendai base16 color plist.\")

(deftheme ono-sendai \"Ono-Sendai 211° Hue-Lock\")
(base16-theme-define 'ono-sendai ono-sendai-theme-colors)

(provide-theme 'ono-sendai)
(provide 'ono-sendai-theme)

;;; ono-sendai-theme.el ends here
"

-- ============================================================
-- §5  Neovim generator
-- ============================================================

def generateNvimPalette : String :=
  "-- ono-sendai/palette.lua
-- 211° Hue-Lock palette generator (integer HSL→RGB, matches Lean implementation)
-- DO NOT EDIT — generated by OnoSendaiGen.lean

local M = {}

local function hsl_to_rgb(h, s, l)
  local s1000 = s * 10
  local l1000 = l * 10
  local twoL = 2 * l1000
  local diff = math.abs(twoL - 1000)
  local c1000 = math.floor((1000 - diff) * s1000 / 1000)
  local hmod = h % 360
  local sector = math.floor(hmod / 60)
  local pair = hmod % 120
  local absVal = math.abs(pair - 60)
  local x1000 = math.floor(c1000 * (60 - absVal) / 60)
  local m1000 = l1000 - math.floor(c1000 / 2)
  local rp, gp, bp
  if sector == 0 then rp, gp, bp = c1000, x1000, 0
  elseif sector == 1 then rp, gp, bp = x1000, c1000, 0
  elseif sector == 2 then rp, gp, bp = 0, c1000, x1000
  elseif sector == 3 then rp, gp, bp = 0, x1000, c1000
  elseif sector == 4 then rp, gp, bp = x1000, 0, c1000
  else rp, gp, bp = c1000, 0, x1000
  end
  local function ch(base)
    return math.min(255, math.max(0, math.floor(((base + m1000) * 255 + 500) / 1000)))
  end
  return ch(rp), ch(gp), ch(bp)
end

local function hsl_hex(h, s, l)
  local r, g, b = hsl_to_rgb(h, s, l)
  return string.format('#%02x%02x%02x', r, g, b)
end

M.levels = { void = 0, deep = 4, night = 8, carbon = 11, github = 16 }

function M.compute(opts)
  opts = opts or {}
  local hero = opts.hero or 211
  local axis = opts.axis or 201
  local level = opts.level or 'carbon'
  local L = M.levels[level] or 11
  return {
    base00 = hsl_hex(211, 12, L + 0),
    base01 = hsl_hex(211, 16, L + 3),
    base02 = hsl_hex(211, 17, L + 8),
    base03 = hsl_hex(211, 15, L + 17),
    base04 = hsl_hex(211, 12, 48),
    base05 = hsl_hex(211, 28, 81),
    base06 = hsl_hex(211, 32, 89),
    base07 = hsl_hex(211, 36, 95),
    base08 = hsl_hex(axis, 100, 86),
    base09 = hsl_hex(axis, 100, 75),
    base0A = hsl_hex(hero, 100, 66),
    base0B = hsl_hex(hero, 100, 57),
    base0C = hsl_hex(hero, 94,  45),
    base0D = hsl_hex(hero, 100, 65),
    base0E = hsl_hex(hero, 100, 71),
    base0F = hsl_hex(hero, 86,  53),
  }
end

return M
"

def generateNvimInit : String :=
  "-- ono-sendai/init.lua
-- 211° Hue-Lock Base16 Theme for Neovim
-- DO NOT EDIT — generated by OnoSendaiGen.lean

local M = {}
local palette = require('ono-sendai.palette')

M.config = {
  hero = 211,
  axis = 201,
  level = 'carbon',
  save_file = vim.fn.stdpath('data') .. '/ono-sendai.json',
}

local function apply_colors(colors)
  -- Reset
  if vim.g.colors_name then
    vim.cmd('highlight clear')
  end
  vim.g.colors_name = 'ono-sendai'
  vim.o.termguicolors = true

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- UI chrome
  hi('Normal',       { fg = colors.base05, bg = colors.base00 })
  hi('NormalFloat',  { fg = colors.base05, bg = colors.base01 })
  hi('CursorLine',  { bg = colors.base01 })
  hi('CursorLineNr',{ fg = colors.base0A, bg = colors.base01 })
  hi('LineNr',      { fg = colors.base03 })
  hi('Visual',      { bg = colors.base02 })
  hi('IncSearch',   { fg = colors.base00, bg = colors.base0A })
  hi('Search',      { fg = colors.base00, bg = colors.base09 })
  hi('StatusLine',  { fg = colors.base05, bg = colors.base01 })
  hi('StatusLineNC',{ fg = colors.base03, bg = colors.base01 })
  hi('VertSplit',   { fg = colors.base02, bg = colors.base00 })
  hi('TabLine',     { fg = colors.base03, bg = colors.base01 })
  hi('TabLineFill', { fg = colors.base03, bg = colors.base00 })
  hi('TabLineSel',  { fg = colors.base05, bg = colors.base02 })
  hi('Pmenu',       { fg = colors.base05, bg = colors.base01 })
  hi('PmenuSel',    { fg = colors.base00, bg = colors.base0A })
  hi('PmenuSbar',   { bg = colors.base02 })
  hi('PmenuThumb',    { bg = colors.base04 })
  hi('WildMenu',      { fg = colors.base00, bg = colors.base0A })
  hi('Folded',        { fg = colors.base03, bg = colors.base01 })
  hi('FoldColumn',    { fg = colors.base03, bg = colors.base00 })
  hi('SignColumn',    { fg = colors.base03, bg = colors.base00 })
  hi('Directory',     { fg = colors.base0D })
  hi('Title',         { fg = colors.base0A, bold = true })
  hi('ErrorMsg',      { fg = colors.base08 })
  hi('WarningMsg',    { fg = colors.base09 })
  hi('MatchParen',    { bg = colors.base02 })
  hi('NonText',       { fg = colors.base02 })
  hi('SpecialKey',    { fg = colors.base02 })

  -- Syntax (base16 mapping)
  hi('Comment',     { fg = colors.base03, italic = true })
  hi('Constant',    { fg = colors.base09 })
  hi('String',      { fg = colors.base0B })
  hi('Character',   { fg = colors.base08 })
  hi('Number',      { fg = colors.base09 })
  hi('Boolean',     { fg = colors.base09 })
  hi('Float',       { fg = colors.base09 })
  hi('Identifier',  { fg = colors.base08 })
  hi('Function',    { fg = colors.base0D })
  hi('Statement',   { fg = colors.base0E })
  hi('Conditional', { fg = colors.base0E })
  hi('Repeat',      { fg = colors.base0E })
  hi('Label',       { fg = colors.base0A })
  hi('Operator',    { fg = colors.base05 })
  hi('Keyword',     { fg = colors.base0E })
  hi('Exception',   { fg = colors.base08 })
  hi('PreProc',     { fg = colors.base0A })
  hi('Include',     { fg = colors.base0D })
  hi('Define',      { fg = colors.base0E })
  hi('Macro',       { fg = colors.base0A })
  hi('Type',        { fg = colors.base0A })
  hi('StorageClass',{ fg = colors.base0A })
  hi('Structure',   { fg = colors.base0A })
  hi('Typedef',     { fg = colors.base0A })
  hi('Special',     { fg = colors.base0C })
  hi('Underlined',  { fg = colors.base0D, underline = true })
  hi('Error',       { fg = colors.base08, bg = colors.base00 })
  hi('Todo',        { fg = colors.base0A, bg = colors.base01 })

  -- Treesitter
  hi('@comment',            { link = 'Comment' })
  hi('@string',             { link = 'String' })
  hi('@number',             { link = 'Number' })
  hi('@function',           { link = 'Function' })
  hi('@function.builtin',   { fg = colors.base0D })
  hi('@keyword',            { link = 'Keyword' })
  hi('@variable',           { fg = colors.base08 })
  hi('@variable.builtin',   { fg = colors.base09 })
  hi('@type',               { link = 'Type' })
  hi('@type.builtin',       { fg = colors.base0A })
  hi('@constant',           { link = 'Constant' })
  hi('@constant.builtin',   { fg = colors.base09 })
  hi('@property',           { fg = colors.base08 })
  hi('@punctuation',        { fg = colors.base04 })
  hi('@punctuation.bracket', { fg = colors.base04 })
  hi('@tag',                { fg = colors.base08 })
  hi('@tag.attribute',      { fg = colors.base0A })

  -- LSP
  hi('DiagnosticError', { fg = colors.base08 })
  hi('DiagnosticWarn',  { fg = colors.base09 })
  hi('DiagnosticInfo',  { fg = colors.base0D })
  hi('DiagnosticHint',  { fg = colors.base0C })

  -- Git
  hi('DiffAdd',    { fg = colors.base0B, bg = colors.base00 })
  hi('DiffChange', { fg = colors.base0D, bg = colors.base00 })
  hi('DiffDelete', { fg = colors.base08, bg = colors.base00 })
  hi('DiffText',   { fg = colors.base0E, bg = colors.base01 })
end

function M.apply()
  local colors = palette.compute({
    hero = M.config.hero,
    axis = M.config.axis,
    level = M.config.level,
  })
  apply_colors(colors)
end

function M.set_hero(hue)
  M.config.hero = hue % 360
  M.apply()
  vim.notify(string.format('Ono-Sendai hero → %d°', M.config.hero))
end

function M.set_axis(hue)
  M.config.axis = hue % 360
  M.apply()
  vim.notify(string.format('Ono-Sendai axis → %d°', M.config.axis))
end

function M.set_level(level)
  if palette.levels[level] then
    M.config.level = level
    M.apply()
    vim.notify(string.format('Ono-Sendai level → %s', level))
  else
    vim.notify('Invalid level: ' .. level, vim.log.levels.ERROR)
  end
end

function M.save()
  local json = vim.fn.json_encode({
    hero = M.config.hero,
    axis = M.config.axis,
    level = M.config.level,
  })
  local f = io.open(M.config.save_file, 'w')
  if f then
    f:write(json)
    f:close()
    vim.notify('Saved to ' .. M.config.save_file)
  end
end

function M.load()
  local f = io.open(M.config.save_file, 'r')
  if f then
    local data = vim.fn.json_decode(f:read('*a'))
    f:close()
    if data then
      M.config.hero = data.hero or M.config.hero
      M.config.axis = data.axis or M.config.axis
      M.config.level = data.level or M.config.level
      M.apply()
    end
  end
end

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', M.config, opts)
  M.load()
  M.apply()
end

-- Telescope picker for black levels
function M.pick_level()
  local ok, pickers = pcall(require, 'telescope.pickers')
  if not ok then
    vim.ui.select(vim.tbl_keys(palette.levels), {
      prompt = 'Black level:',
    }, function(choice)
      if choice then M.set_level(choice) end
    end)
    return
  end
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local action_set = require('telescope.actions.set')
  pickers.new(require('telescope.themes').get_dropdown(), {
    prompt_title = 'Ono-Sendai Black Level',
    finder = finders.new_table({ results = { 'void', 'deep', 'night', 'carbon', 'github' } }),
    sorter = conf.generic_sorter(),
    attach_mappings = function(bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(bufnr)
        M.set_level(entry[1])
      end)
      action_set.shift_selection:enhance({
        post = function()
          M.set_level(action_state.get_selected_entry()[1])
        end
      })
      return true
    end,
  }):find()
end

return M
"

def generateNvimPlugin : String :=
  "-- plugin/ono-sendai.lua
-- Commands for the Ono-Sendai theme
-- DO NOT EDIT — generated by OnoSendaiGen.lean

vim.api.nvim_create_user_command('OnoSendaiHero', function(opts)
  require('ono-sendai').set_hero(tonumber(opts.args) or 211)
end, { nargs = 1, desc = 'Set Ono-Sendai hero hue (0-359)' })

vim.api.nvim_create_user_command('OnoSendaiAxis', function(opts)
  require('ono-sendai').set_axis(tonumber(opts.args) or 201)
end, { nargs = 1, desc = 'Set Ono-Sendai axis hue (0-359)' })

vim.api.nvim_create_user_command('OnoSendaiLevel', function(opts)
  require('ono-sendai').set_level(opts.args)
end, {
  nargs = 1,
  desc = 'Set Ono-Sendai black level',
  complete = function()
    return { 'void', 'deep', 'night', 'carbon', 'github' }
  end,
})

vim.api.nvim_create_user_command('OnoSendaiSave', function()
  require('ono-sendai').save()
end, { desc = 'Save Ono-Sendai palette' })

vim.api.nvim_create_user_command('OnoSendaiPick', function()
  require('ono-sendai').pick_level()
end, { desc = 'Pick Ono-Sendai black level (Telescope)' })
"
