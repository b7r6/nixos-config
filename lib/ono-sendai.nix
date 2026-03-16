# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                  // ono-sendai // color-math
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Pure Nix implementation mirroring the Lean4 reference (nix/packages/ono-sendai-generator/)
#
# The Lean implementation uses bounded types (Fin 256, Fin 360, Fin 101) for
# compile-time safety. This Nix version uses runtime clamping to match.
#
# Core invariants:
#   - Grayscale ramp locked to 211 hue
#   - Hero hue controls base0A-0F (classes, strings, functions, keywords)
#   - Axis hue controls base08-09 (variables, integers - the cool shift)

{ lib }:

let
  # Integer math helpers (matching Lean's integer division semantics)
  clamp =
    min: max: x:
    if x < min then
      min
    else if x > max then
      max
    else
      x;
  abs = x: if x < 0 then -x else x;

  # Proper modulo (handles negative numbers correctly)
  mod =
    a: b:
    let
      r = a - (a / b) * b;
    in
    if r < 0 then r + b else r;

  # HSL to RGB conversion
  # Uses integer math scaled by 1000 to avoid floating point
  # This exactly matches the Lean implementation in OnoSendaiGen.lean:65-86
  hsl-to-rgb =
    h: s: l:
    let
      s1000 = s * 10;
      l1000 = l * 10;
      two-l = 2 * l1000;
      diff = abs (two-l - 1000);
      c1000 = ((1000 - diff) * s1000) / 1000;
      hmod = mod h 360;
      sector = hmod / 60;
      pair = mod hmod 120;
      abs-val = abs (pair - 60);
      x1000 = (c1000 * (60 - abs-val)) / 60;
      m1000 = l1000 - c1000 / 2;

      # RGB components by sector
      rgb-base =
        if sector == 0 then
          {
            r = c1000;
            g = x1000;
            b = 0;
          }
        else if sector == 1 then
          {
            r = x1000;
            g = c1000;
            b = 0;
          }
        else if sector == 2 then
          {
            r = 0;
            g = c1000;
            b = x1000;
          }
        else if sector == 3 then
          {
            r = 0;
            g = x1000;
            b = c1000;
          }
        else if sector == 4 then
          {
            r = x1000;
            g = 0;
            b = c1000;
          }
        else
          {
            r = c1000;
            g = 0;
            b = x1000;
          };

      # Channel conversion with rounding
      ch =
        base:
        let
          val = ((base + m1000) * 255 + 500) / 1000;
        in
        clamp 0 255 val;
    in
    {
      r = ch rgb-base.r;
      g = ch rgb-base.g;
      b = ch rgb-base.b;
    };

  # RGB to hex string
  rgb-to-hex =
    rgb:
    let
      hex-digit =
        n:
        let
          chars = "0123456789abcdef";
        in
        builtins.substring n 1 chars;
      to-hex =
        n:
        let
          hi = n / 16;
          lo = mod n 16;
        in
        "${hex-digit hi}${hex-digit lo}";
    in
    "#${to-hex rgb.r}${to-hex rgb.g}${to-hex rgb.b}";

  # HSL to hex (the main interface)
  hsl-to-hex =
    h: s: l:
    rgb-to-hex (hsl-to-rgb h s l);

  # Black level base lightness values
  # Matches Lean's BlackLevel.baseL
  black-levels = {
    void = 0; # L=0%  - true black (kills thin fonts)
    deep = 4; # L=4%  - hand-tuned
    night = 8; # L=8%  - OLED threshold
    carbon = 11; # L=11% - good default
    github = 16; # L=16% - matches GitHub dark
  };

  # Generate a complete base16 palette
  # Matches Lean's makePalette in OnoSendaiGen.lean:136-154
  make-palette =
    {
      level ? "carbon",
      hero-hue ? 211,
      axis-hue ? 201,
    }:
    let
      L = black-levels.${level} or 11;
      # 211 hue helpers for grayscale
      g = hsl-to-hex 211;
      # Hero and axis hue helpers
      hero = hsl-to-hex hero-hue;
      axis = hsl-to-hex axis-hue;
    in
    {
      # Grayscale ramp - always 211 hue, only lightness varies
      base00 = g 12 (L + 0); # Background
      base01 = g 16 (L + 3); # Raised surfaces
      base02 = g 17 (L + 8); # Selections
      base03 = g 15 (L + 17); # Comments
      base04 = g 12 48; # Dark foreground
      base05 = g 28 81; # Default foreground
      base06 = g 32 89; # Light foreground
      base07 = g 36 95; # Light background

      # Axis hue - cool shift for variables/integers
      base08 = axis 100 86; # Variables (ice blue)
      base09 = axis 100 75; # Integers (sky blue)

      # Hero hue - primary accent colors
      base0A = hero 100 66; # Classes (HERO - the heresy)
      base0B = hero 100 57; # Strings (deep)
      base0C = hero 94 45; # Support (desaturated)
      base0D = hero 100 65; # Functions (link blue)
      base0E = hero 100 71; # Keywords (soft)
      base0F = hero 86 53; # Deprecated (corp blue)
    };

  # Named palette variants (for quick access)
  variants = {
    # Classic ono-sendai variants at default hues (211/201)
    void = make-palette { level = "void"; };
    deep = make-palette { level = "deep"; };
    night = make-palette { level = "night"; };
    carbon = make-palette { level = "carbon"; };
    github = make-palette { level = "github"; };

    # Aliases from the original config
    chiba = make-palette { level = "deep"; }; # L=4%
    razorgirl = make-palette { level = "night"; }; # L=8%
    sprawl = make-palette { level = "carbon"; }; # L=11%
  };

  # Create a theme attrset suitable for stylix
  mk-theme =
    {
      level,
      hero-hue ? 211,
      axis-hue ? 201,
    }:
    let
      palette = make-palette { inherit level hero-hue axis-hue; };
      level-name = if builtins.isString level then level else "custom";
    in
    {
      slug = "ono-sendai-${level-name}";
      name = "Ono-Sendai ${lib.toUpper (builtins.substring 0 1 level-name)}${
        builtins.substring 1 (-1) level-name
      }";
      author = "b7r6";
      variant = "dark";
      inherit
        palette
        hero-hue
        axis-hue
        level
        ;
    };

in
{
  inherit
    hsl-to-rgb
    rgb-to-hex
    hsl-to-hex
    black-levels
    make-palette
    variants
    mk-theme
    ;
}
