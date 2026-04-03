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

  themes = {
    ono-sendai = import ./palettes/ono-sendai-blue.nix;
    ono-sendai-tactical = import ./palettes/ono-sendai-tactical.nix;
  };

  themeVariants = lib.unique (
    lib.flatten (lib.mapAttrsToList (_: theme: lib.attrNames theme) themes)
  );

  berkeleyMono = pkgs.callPackage ./fonts/berkeley-mono { };
  currentTheme = themes.${cfg.theme}.${cfg.variant};

  fontConfig = rec {
    package = berkeleyMono;
    name = "Berkeley Mono";

    weights = {
      light = "${name} Light";
      regular = "${name} Regular";
      medium = "${name} Medium";
      semibold = "${name} SemiBold";
      bold = "${name} Bold";
    };

    monospace = {
      inherit package;
      name =
        if cfg.display.highDPI && cfg.display.width >= 3840 then
          weights.semibold
        else if cfg.display.highDPI then
          weights.semibold
        else
          weights.semibold;
    };

    sizes =
      let
        baseSizes = {
          desktop = 16;
          applications = 16;
          terminal = 14;
          popups = 16;
        };

        scaleFactor = 1.0;
      in
      lib.mapAttrs (_: size: lib.toInt (size * scaleFactor)) baseSizes;

    sansSerif = {
      inherit package;
      name = weights.medium;
    };
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

    theme = mkOption {
      type = types.enum (lib.attrNames themes);
      default = "ono-sendai";
      description = "Theme family to use";
    };

    variant = mkOption {
      type = types.enum themeVariants;
      default = "chiba";
      description = "Theme variant within the family";
    };

    palette = mkOption {
      type = types.attrs;
      description = "The resolved base16 theme palette";
      internal = true;
      readOnly = true;
      default = currentTheme.palette;
    };

    # font rendering and wallpaper generation
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
        description = "Display profile for optimizations";
      };

      highDPI = mkOption {
        type = types.bool;
        default = false;
        description = "Enable high-DPI adjustments";
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

    # Override options for fine-tuning
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
    stylix = {
      enable = true;
      autoEnable = true;

      # Use generated wallpaper if enabled, fallback to static
      image =
        if config.hyper-modern-nixos.wallpaper.enable then
          "${config.hyper-modern-nixos.wallpaper.package}/wallpaper.png"
        else
          ./assets/hyper-modern-nixos-wallpaper-0x01.png;

      # Stylix wants just the color values
      base16Scheme = currentTheme.palette;

      fonts = {
        inherit (fontConfig) monospace;
        inherit (fontConfig) sansSerif;
        serif = fontConfig.monospace;

        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };

        sizes = fontConfig.sizes // cfg.overrides.fontSizes;
      };

      opacity = {
        terminal = if cfg.display.profile == "oled" then 0.98 else 0.95;
        desktop = 0.95;
        popups = 0.95;
      }
      // cfg.overrides.opacity;
    };

    home.sessionVariables = mkMerge [
      (mkIf (cfg.enable && cfg.display.profile == "samsung-e6") {
        FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 truetype:interpreter-version=40";
      })

      (mkIf (cfg.enable && cfg.display.profile == "lg-ultragear-oled") {
        FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0 truetype:interpreter-version=40 lcdfilter:lcddefault";
        COLORTERM = "truecolor";
        __GL_YIELD = "USLEEP";
        MESA_VK_WSI_PRESENT_MODE = "immediate";
      })

      (mkIf (cfg.enable && cfg.display.profile == "oled") {
        FREETYPE_PROPERTIES = "truetype:interpreter-version=40 lcdfilter:lcdnone";
        COLORTERM = "truecolor";
      })

      (mkIf (cfg.enable && cfg.display.profile == "high-contrast") {
        FREETYPE_PROPERTIES = "cff:no-stem-darkening=1 autofitter:no-stem-darkening=1 truetype:interpreter-version=35";
      })
    ];

    hyper-modern-nixos.wallpaper.enable = true;

    hyper-modern-nixos.wallpaper.customize = {
      inherit (cfg.display) profile width height;
      theme = currentTheme;
      dpi = if cfg.display.highDPI then 192 else 96;
    };
  };
}
