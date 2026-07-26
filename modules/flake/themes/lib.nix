# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                    // ono-sendai // color-math
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

  # White level base lightness values for the maas (light) polarity
  # Matches Lean's WhiteLevel.baseL
  white-levels = {
    tessier = 100; # L=100% - clinical pure white
    neoform = 97; # L=97%  - default near-white
    ghost = 92; # L=92%  - fog
  };

  # Generate a complete base16 palette
  # Matches Lean's makePalette in OnoSendaiGen.lean:136-154
  # The manufacturer axis: the night ramp hue is family-owned (mirror of
  # the Lean PaletteFamily). straylight = the 211° house; hosaka = 165°
  # blackwell phosphor.
  family-dark-ramp-hue = {
    straylight = 211;
    hosaka = 165;
  };

  make-palette =
    {
      level ? "carbon",
      hero-hue ? 211,
      axis-hue ? 201,
      family ? "straylight",
    }:
    let
      L = black-levels.${level} or 11;
      # family ramp hue helpers for grayscale
      g = hsl-to-hex (family-dark-ramp-hue.${family} or 211);
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

  # Generate a maas (light) base16 palette
  # Matches Lean's makePaletteLight — same 211 lock, ramp descending from the
  # white level, accents cut deep for paper. ramp-hue unlocks the paper tint
  # for warm variants (bioptic = neoform + ramp-hue 36).
  make-palette-light =
    {
      level ? "neoform",
      hero-hue ? 211,
      axis-hue ? 201,
      ramp-hue ? 211,
    }:
    let
      W = white-levels.${level} or 97;
      g = hsl-to-hex ramp-hue;
      hero = hsl-to-hex hero-hue;
      axis = hsl-to-hex axis-hue;
    in
    {
      # Ramp descends from the white level
      base00 = g 33 (W - 0); # Background (paper)
      base01 = g 28 (W - 4); # Raised surfaces (card)
      base02 = g 26 (W - 10); # Selections / borders
      base03 = g 15 60; # Comments (muted)
      base04 = g 15 43; # Dark foreground
      base05 = g 23 23; # Default foreground (ink)
      base06 = g 25 15; # Darker ink
      base07 = g 28 8; # Near-black text

      # Axis hue - deepened for light ground
      base08 = axis 90 40; # Variables
      base09 = axis 100 34; # Integers

      # Hero hue - the dark side's deep cuts become primary on paper
      base0A = hero 94 45; # Classes (= dark base0C formula)
      base0B = hero 100 40; # Strings
      base0C = hero 100 34; # Support
      base0D = hero 86 47; # Functions
      base0E = hero 100 50; # Keywords
      base0F = hero 86 38; # Deprecated
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

    # Maas (light) variants — the day pole
    tessier = make-palette-light { level = "tessier"; };
    neoform = make-palette-light { level = "neoform"; };
    ghost = make-palette-light { level = "ghost"; };
    bioptic = make-palette-light {
      level = "neoform";
      ramp-hue = 36;
    }; # warm clinical paper
  };

  # Create a theme attrset suitable for stylix
  mk-theme =
    {
      level,
      hero-hue ? 211,
      axis-hue ? 201,
      polarity ? "dark",
      ramp-hue ? 211,
    }:
    let
      light = polarity == "light";
      palette =
        if light then
          make-palette-light {
            inherit
              level
              hero-hue
              axis-hue
              ramp-hue
              ;
          }
        else
          make-palette { inherit level hero-hue axis-hue; };
      level-name = if builtins.isString level then level else "custom";
      family = if light then "maas" else "ono-sendai";
      family-display = if light then "Maas" else "Ono-Sendai";
    in
    {
      slug = "${family}-${level-name}";
      name = "${family-display} ${lib.toUpper (builtins.substring 0 1 level-name)}${
        builtins.substring 1 (-1) level-name
      }";
      author = "b7r6";
      variant = polarity;
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
    white-levels
    make-palette
    make-palette-light
    variants
    mk-theme
    ;
}
