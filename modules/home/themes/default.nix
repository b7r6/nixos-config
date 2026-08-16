# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // themes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Ono-Sendai theme system with two modes:
#   1. Computed palettes via HSL color math (hero-hue + axis-hue)
#   2. Legacy pre-baked palettes (theme + variant)
#
# 211° hue-locked grayscale ramp with two degrees of freedom:
#   - hero-hue: controls accent colors (base0A-0F)
#   - axis-hue: controls variable/integer colors (base08-09)
#
{
  flake,
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (flake) inputs;
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    mkMerge
    types
    ;

  cfg = config.hyper-modern-nixos.themes;

  # Import color math library (lives in the themes flake-parts component)
  color-lib = import ../../flake/themes/lib.nix { inherit lib; };

  # Legacy pre-baked palettes (backward compatibility)
  legacyThemes = {
    ono-sendai = import ./palettes/ono-sendai-blue.nix;
    ono-sendai-tactical = import ./palettes/ono-sendai-tactical.nix;
  };

  legacyVariants = lib.unique (
    lib.flatten (lib.mapAttrsToList (_: theme: lib.attrNames theme) legacyThemes)
  );

  # Resolve the current theme
  currentTheme =
    if cfg.mode == "computed" then
      color-lib.mk-theme {
        inherit (cfg)
          level
          hero-hue
          axis-hue
          polarity
          ramp-hue
          ;
      }
    else
      legacyThemes.${cfg.theme}.${cfg.variant};

  # Font configuration
  berkeleyMono = pkgs.callPackage ./fonts/berkeley-mono { };

  fontWeights = {
    light = "Berkeley Mono Light";
    regular = "Berkeley Mono";
    medium = "Berkeley Mono Medium";
    semibold = "Berkeley Mono SemiBold";
    bold = "Berkeley Mono Bold";
  };

  # Select font weight based on display profile
  selectFontWeight =
    profile: dpi:
    if profile == "oled" || profile == "lg-ultragear-oled" then
      fontWeights.semibold
    else if dpi >= 192 then
      fontWeights.semibold
    else
      fontWeights.medium;

  baseFontSizes = {
    desktop = 16;
    applications = 16;
    terminal = 14;
    popups = 16;
  };

in
{
  imports = [
    inputs.stylix.homeModules.stylix
    ./wallpapers
  ];

  options.hyper-modern-nixos.themes = {
    enable = mkEnableOption "hyper-modern theming system" // {
      default = true;
    };

    # Mode selection: computed vs legacy
    mode = mkOption {
      type = types.enum [
        "computed"
        "legacy"
      ];
      default = "legacy";
      description = ''
        Theme mode:
          computed - Generate palette from HSL color math (hero-hue + axis-hue)
          legacy   - Use pre-baked palette (theme + variant)
      '';
    };

    # ── Computed mode options ──────────────────────────────────────────────────

    polarity = mkOption {
      type = types.enum [
        "dark"
        "light"
      ];
      default = "dark";
      description = ''
        Luminance polarity (computed mode):
          dark  - ono-sendai (black levels)
          light - maas (white levels)
      '';
    };

    level = mkOption {
      type = types.enum [
        # dark (ono-sendai) black levels
        "void"
        "deep"
        "night"
        "carbon"
        "github"
        # light (maas) white levels
        "tessier"
        "neoform"
        "ghost"
      ];
      default = "carbon";
      description = ''
        Luminance level variant (computed mode).

        Dark (ono-sendai) black levels:
          void    - L=0%   (true black, kills thin fonts)
          deep    - L=4%   (hand-tuned dark)
          night   - L=8%   (OLED safe threshold)
          carbon  - L=11%  (recommended default)
          github  - L=16%  (matches GitHub dark mode)

        Light (maas) white levels:
          tessier - L=100% (clinical pure white)
          neoform - L=97%  (recommended light default)
          ghost   - L=92%  (fog)
      '';
    };

    hero-hue = mkOption {
      type = types.ints.between 0 359;
      default = 211;
      description = "Hero accent hue (0-359). Controls base0A-0F.";
    };

    axis-hue = mkOption {
      type = types.ints.between 0 359;
      default = 201;
      description = "Axis accent hue (0-359). Controls base08-09.";
    };

    ramp-hue = mkOption {
      type = types.ints.between 0 359;
      default = 211;
      description = ''
        Grayscale-ramp hue (light polarity only). Unlocks the paper tint for
        warm variants — bioptic is neoform + ramp-hue 36. Dark ramps stay
        locked to 211.
      '';
    };

    # ── Legacy mode options ────────────────────────────────────────────────────

    theme = mkOption {
      type = types.enum (lib.attrNames legacyThemes);
      default = "ono-sendai";
      description = "Theme family (legacy mode)";
    };

    variant = mkOption {
      type = types.enum legacyVariants;
      default = "razorgirl";
      description = "Theme variant within the family (legacy mode)";
    };

    # ── Computed outputs (read-only) ───────────────────────────────────────────

    palette = mkOption {
      type = types.attrs;
      description = "The resolved base16 theme palette";
      internal = true;
      readOnly = true;
      default = currentTheme.palette;
    };

    resolved = mkOption {
      type = types.attrs;
      description = "The full resolved theme configuration";
      internal = true;
      readOnly = true;
      default = currentTheme;
    };

    # ── Display configuration ──────────────────────────────────────────────────

    display = {
      profile = mkOption {
        type = types.enum [
          "generic"
          "oled"
          "samsung-e6"
          "lg-ultragear-oled"
          "high-contrast"
        ];
        default = "generic";
        description = "Display profile for font/opacity tuning";
      };

      highDPI = mkOption {
        type = types.bool;
        default = false;
        description = "Enable high-DPI adjustments";
      };

      dpi = mkOption {
        type = types.int;
        default = if cfg.display.highDPI then 192 else 96;
        description = "Display DPI";
      };

      width = mkOption {
        type = types.int;
        default = 2560;
        description = "Display width for wallpaper generation";
      };

      height = mkOption {
        type = types.int;
        default = 1440;
        description = "Display height for wallpaper generation";
      };
    };

    # ── Override options ───────────────────────────────────────────────────────

    overrides = {
      fontSizes = mkOption {
        type = types.attrsOf types.int;
        default = { };
        description = "Override specific font sizes";
        example = {
          terminal = 18;
        };
      };

      opacity = mkOption {
        type = types.attrsOf types.float;
        default = { };
        description = "Override opacity values";
        example = {
          terminal = 0.95;
        };
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          cfg.mode != "computed"
          || (
            if cfg.polarity == "light" then
              builtins.elem cfg.level [ "tessier" "neoform" "ghost" ]
            else
              builtins.elem cfg.level [ "void" "deep" "night" "carbon" "github" ]
          );
        message = ''
          hyper-modern-nixos.themes: level "${cfg.level}" does not belong to the
          "${cfg.polarity}" polarity (dark levels: void/deep/night/carbon/github,
          light levels: tessier/neoform/ghost).
        '';
      }
    ];

    stylix = {
      enable = true;
      autoEnable = true;

      # Drives the xdg-desktop-portal color-scheme (the live day/night channel
      # GTK/Qt apps actually follow) alongside the palette itself.
      polarity = cfg.polarity;

      # Stylix's per-package theming overlay sets `nixpkgs.overlays` inside the
      # home-manager module. Under nixos-unified's `home-manager.useGlobalPkgs`
      # (set in modules/nixos/base.nix), home shares the NixOS/perSystem
      # pkgs and home-level `nixpkgs.overlays` is forbidden — home-manager warns
      # now and will hard-error soon. We don't rely on stylix's package overlay
      # (theming is driven by base16Scheme + the explicit target configs below),
      # so disable it to keep a single, clean overlay tree.
      overlays.enable = false;

      # Use generated wallpaper if enabled, fallback to static
      image =
        if config.hyper-modern-nixos.wallpaper.enable then
          "${config.hyper-modern-nixos.wallpaper.package}/wallpaper.png"
        else
          ./assets/hyper-modern-nixos-wallpaper-0x01.png;

      # Stylix wants just the color values
      base16Scheme = currentTheme.palette;

      fonts = {
        monospace = {
          package = berkeleyMono;
          name = selectFontWeight cfg.display.profile cfg.display.dpi;
        };

        sansSerif = {
          package = berkeleyMono;
          name = fontWeights.medium;
        };

        serif = {
          package = berkeleyMono;
          name = fontWeights.regular;
        };

        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };

        sizes = baseFontSizes // cfg.overrides.fontSizes;
      };

      opacity = {
        terminal =
          if cfg.display.profile == "oled" || cfg.display.profile == "lg-ultragear-oled" then 0.98 else 0.95;
        desktop = 0.95;
        popups = 0.95;
      }
      // cfg.overrides.opacity;
    };

    # Display-profile-specific environment variables
    home.sessionVariables = mkMerge [
      (mkIf (cfg.display.profile == "samsung-e6") {
        FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 truetype:interpreter-version=40";
      })

      (mkIf (cfg.display.profile == "lg-ultragear-oled") {
        FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 truetype:interpreter-version=40 lcdfilter:lcddefault";
        COLORTERM = "truecolor";
        __GL_YIELD = "USLEEP";
        MESA_VK_WSI_PRESENT_MODE = "immediate";
      })

      (mkIf (cfg.display.profile == "oled") {
        FREETYPE_PROPERTIES = "truetype:interpreter-version=40 lcdfilter:lcdnone";
        COLORTERM = "truecolor";
      })

      (mkIf (cfg.display.profile == "high-contrast") {
        FREETYPE_PROPERTIES = "cff:no-stem-darkening=1 autofitter:no-stem-darkening=1 truetype:interpreter-version=35";
      })
    ];

    # Enable wallpaper generation
    hyper-modern-nixos.wallpaper.enable = true;
    hyper-modern-nixos.wallpaper.customize = {
      inherit (cfg.display) profile width height;
      theme = currentTheme;
      dpi = cfg.display.dpi;
    };
  };
}
