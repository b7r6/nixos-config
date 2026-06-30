# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // new-suzuki // preset data
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Preset studies for the affluent ↔ facility × day ↔ night space.
# Pure data — no module wrapping. Consumed by both default.nix (for the
# initial palette) and themes.nix (for the theme-switch script).
#
# QML colors are #AARRGGBB (alpha-first).
{
  # ════════════════════════════════════════════════════════════════════════
  # AFFLUENT × DAY
  # ════════════════════════════════════════════════════════════════════════
  villa-straylight = {
    label = "villa-straylight";
    family = "affluent";
    polarity = 0.0;
    luminance = 0.0;
    tokens = {
      ink = "#33302a";
      ink-muted = "#5c574e";
      ink-faint = "#8a8378";
      ink-ghost = "#bfb8ac";
      surface = "#faf8f5";
      paper = "#f0ece5";
      border = "#e2dcd2";
      accent = "#0969da";
      accent-d = "#218bff";
      glass-edge = "#210969da";
      glass-fill = "#80f0ece5";
      glass-fill-hover = "#99e2dcd2";
      shadow = "#14faf8f5";
      success = "#1f6feb";
      warn = "#c4762c";
      error = "#c0392b";
    };
    aesthetic = {
      textCase = "lowercase";
      gaps-inner = 8;
      gaps-outer = 16;
      kerning = "relaxed";
      anim-duration = 500;
      anim-easing = "expo_out";
      entrance-direction = "fade-up";
      entrance-offset = 14;
      scanlines = false;
      scanline-idle = 0;
      opacity = 0.92;
      border-weight = 1;
      border-alpha = 0.15;
      shadow-enabled = true;
      shadow-alpha = 0.08;
      grain = 0.03;
      grain-warm = true;
      label-prefix = "";
    };
  };

  # ════════════════════════════════════════════════════════════════════════
  # AFFLUENT × DUSK
  # ════════════════════════════════════════════════════════════════════════
  onsen = {
    label = "onsen";
    family = "affluent";
    polarity = 0.0;
    luminance = 0.3;
    tokens = {
      ink = "#2d2820";
      ink-muted = "#5c5447";
      ink-faint = "#8a7e6b";
      ink-ghost = "#c4b8a4";
      surface = "#faf6f0";
      paper = "#f0ebe2";
      border = "#ddd5c8";
      accent = "#c4762c";
      accent-d = "#e8a05c";
      glass-edge = "#21c4762c";
      glass-fill = "#80f0ebe2";
      glass-fill-hover = "#99ddd5c8";
      shadow = "#14faf6f0";
      success = "#7a9c5a";
      warn = "#c4762c";
      error = "#a04030";
    };
    aesthetic = {
      textCase = "lowercase";
      gaps-inner = 8;
      gaps-outer = 14;
      kerning = "relaxed";
      anim-duration = 500;
      anim-easing = "expo_out";
      entrance-direction = "fade-up";
      entrance-offset = 14;
      scanlines = false;
      scanline-idle = 0;
      opacity = 0.9;
      border-weight = 1;
      border-alpha = 0.12;
      shadow-enabled = true;
      shadow-alpha = 0.06;
      grain = 0.04;
      grain-warm = true;
      label-prefix = "";
    };
  };

  # ════════════════════════════════════════════════════════════════════════
  # AFFLUENT × NIGHT
  # ════════════════════════════════════════════════════════════════════════
  razorgirl = {
    label = "razorgirl";
    family = "affluent";
    polarity = 0.0;
    luminance = 1.0;
    tokens = {
      ink = "#d8e0e7";
      ink-muted = "#6b7689";
      ink-faint = "#3a424f";
      ink-ghost = "#2a3039";
      surface = "#111417";
      paper = "#181c21";
      border = "#21262d";
      accent = "#54aeff";
      accent-d = "#80ccff";
      glass-edge = "#2154aeff";
      glass-fill = "#80181c21";
      glass-fill-hover = "#9921262d";
      shadow = "#14111417";
      success = "#218bff";
      warn = "#54aeff";
      error = "#f85149";
    };
    aesthetic = {
      textCase = "lowercase";
      gaps-inner = 6;
      gaps-outer = 12;
      kerning = "relaxed";
      anim-duration = 400;
      anim-easing = "expo_out";
      entrance-direction = "fade-up";
      entrance-offset = 10;
      scanlines = false;
      scanline-idle = 0;
      opacity = 0.9;
      border-weight = 1;
      border-alpha = 0.13;
      shadow-enabled = true;
      shadow-alpha = 0.08;
      grain = 0.05;
      grain-warm = false;
      label-prefix = "";
    };
  };

  # ════════════════════════════════════════════════════════════════════════
  # THE SPRAWL — transitional, night-leaning
  # ════════════════════════════════════════════════════════════════════════
  chiba = {
    label = "chiba";
    family = "sprawl";
    polarity = 0.4;
    luminance = 0.8;
    tokens = {
      ink = "#d8e0e7";
      ink-muted = "#6b7689";
      ink-faint = "#3a424f";
      ink-ghost = "#2a3039";
      surface = "#191c20";
      paper = "#1f232a";
      border = "#2a3039";
      accent = "#54aeff";
      accent-d = "#80ccff";
      glass-edge = "#2154aeff";
      glass-fill = "#991f232a";
      glass-fill-hover = "#cc2a3039";
      shadow = "#0a191c20";
      success = "#218bff";
      warn = "#54aeff";
      error = "#f85149";
    };
    aesthetic = {
      textCase = "lowercase";
      gaps-inner = 4;
      gaps-outer = 8;
      kerning = "normal";
      anim-duration = 250;
      anim-easing = "expo_out";
      entrance-direction = "fade-up";
      entrance-offset = 8;
      scanlines = false;
      scanline-idle = 30;
      opacity = 0.95;
      border-weight = 1;
      border-alpha = 0.2;
      shadow-enabled = false;
      shadow-alpha = 0.04;
      grain = 0.03;
      grain-warm = false;
      label-prefix = "";
    };
  };

  # ════════════════════════════════════════════════════════════════════════
  # FACILITY × DAY
  # ════════════════════════════════════════════════════════════════════════
  bunker = {
    label = "bunker";
    family = "facility";
    polarity = 1.0;
    luminance = 0.0;
    tokens = {
      ink = "#1a2028";
      ink-muted = "#424d5b";
      ink-faint = "#6b7a8a";
      ink-ghost = "#9aa8b8";
      surface = "#f5f7fa";
      paper = "#e8ecf2";
      border = "#c8d1dc";
      accent = "#cc0000";
      accent-d = "#ff3333";
      glass-edge = "#00c80000";
      glass-fill = "#ffe8ecf2";
      glass-fill-hover = "#ffd4dbe6";
      shadow = "#00f5f7fa";
      success = "#0066cc";
      warn = "#cc7700";
      error = "#cc0000";
    };
    aesthetic = {
      textCase = "uppercase";
      gaps-inner = 4;
      gaps-outer = 8;
      kerning = "tight";
      anim-duration = 150;
      anim-easing = "step";
      entrance-direction = "drop-top";
      entrance-offset = 20;
      scanlines = true;
      scanline-idle = 5;
      opacity = 1.0;
      border-weight = 1;
      border-alpha = 0.5;
      shadow-enabled = false;
      shadow-alpha = 0.0;
      grain = 0.0;
      grain-warm = false;
      label-prefix = "//";
    };
  };

  # ════════════════════════════════════════════════════════════════════════
  # FACILITY × NIGHT
  # ════════════════════════════════════════════════════════════════════════
  yorha = {
    label = "yorha";
    family = "facility";
    polarity = 1.0;
    luminance = 1.0;
    tokens = {
      ink = "#e6f7ff";
      ink-muted = "#8b9bb0";
      ink-faint = "#3a4a5a";
      ink-ghost = "#1a2a3a";
      surface = "#000000";
      paper = "#0a0d10";
      border = "#1a1f24";
      accent = "#ff0040";
      accent-d = "#ff4470";
      glass-edge = "#00ff0040";
      glass-fill = "#ff0a0d10";
      glass-fill-hover = "#ff1a1f24";
      shadow = "#00000000";
      success = "#00cc60";
      warn = "#ffaa00";
      error = "#ff0040";
    };
    aesthetic = {
      textCase = "uppercase";
      gaps-inner = 2;
      gaps-outer = 4;
      kerning = "tight";
      anim-duration = 100;
      anim-easing = "step";
      entrance-direction = "glitch-snap";
      entrance-offset = 20;
      scanlines = true;
      scanline-idle = 5;
      opacity = 1.0;
      border-weight = 1;
      border-alpha = 0.6;
      shadow-enabled = false;
      shadow-alpha = 0.0;
      grain = 0.0;
      grain-warm = false;
      label-prefix = "//";
    };
  };
}
