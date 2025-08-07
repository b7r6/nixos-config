#
# // hypermodern // terminals
#
# "the matrix has its roots in primitive arcade games."
#
{ config, lib, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.terminals;

  # sophisticated cursor aesthetics for different contexts
  cursorProfiles = {
    # minimal distraction - steady focus
    zen = {
      style = "SteadyBlock";
      blinkRate = 0;
    };
    # classic terminal feel - rhythmic presence
    vintage = {
      style = "BlinkingBlock";
      blinkRate = 750;
    };
    # high performance - responsive indication
    performance = {
      style = "BlinkingBar";
      blinkRate = 300;
    };
    # writing mode - gentle underlining
    writer = {
      style = "BlinkingUnderline";
      blinkRate = 1000;
    };
  };

  # font feature combinations for different use cases
  fontFeatures = {
    # programming ligatures and stylistic sets
    code = [
      "liga"
      "calt"
      "ss01"
      "ss02"
      "ss03"
      "ss04"
    ];
    # clean reading experience
    text = [
      "liga"
      "calt"
    ];
    # maximum compatibility
    legacy = [ ];
    # custom user selection
    custom = cfg.font.customFeatures;
  };

  # intelligent padding based on screen real estate
  paddingProfiles = {
    # minimal - maximum terminal space
    compact = 5;
    # balanced - good visual breathing room
    comfortable = 15;
    # spacious - cinematic terminal experience
    luxurious = 25;
    # user-defined
    custom = cfg.aesthetic.customPadding;
  };
in
{
  options.hyper-modern-nixos.terminals = {
    enable = mkEnableOption "// hypermodern // terminals" // {
      default = true;
    };

    # unified aesthetic configuration
    aesthetic = {
      cursorProfile = mkOption {
        type = types.enum [
          "zen"
          "vintage"
          "performance"
          "writer"
          "custom"
        ];
        default = "performance";
        description = ''
          Cursor behavior profile:
          • zen: steady, unblinking - for deep focus
          • vintage: classic blinking block - traditional terminal feel
          • performance: fast blinking bar - responsive visual feedback
          • writer: gentle underline - for text composition
          • custom: user-defined via cursor.* options
        '';
      };

      paddingProfile = mkOption {
        type = types.enum [
          "compact"
          "comfortable"
          "luxurious"
          "custom"
        ];
        default = "comfortable";
        description = ''
          Terminal padding aesthetic:
          • compact: minimal spacing (5px) - maximize screen real estate
          • comfortable: balanced spacing (15px) - optimal readability  
          • luxurious: generous spacing (25px) - cinematic experience
          • custom: user-defined via customPadding option
        '';
      };

      customPadding = mkOption {
        type = types.int;
        default = 15;
        description = "Custom padding when paddingProfile is 'custom'";
      };

      transparency = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable terminal transparency for desktop integration";
        };

        opacity = mkOption {
          type = types.float;
          default = 0.9;
          description = "Terminal opacity level (0.0 to 1.0)";
        };
      };
    };

    # sophisticated font handling
    font = {
      family = mkOption {
        type = types.str;
        default = "Berkeley Mono";
        description = "Primary terminal font - the foundation of your digital aesthetic";
        example = "JetBrains Mono";
      };

      weight = mkOption {
        type = types.str;
        default = "Regular";
        description = "Font weight for optimal readability at your preferred size";
        example = "Medium";
      };

      size = mkOption {
        type = types.int;
        default = 13;
        description = "Font size - balance between information density and readability";
      };

      featureProfile = mkOption {
        type = types.enum [
          "code"
          "text"
          "legacy"
          "custom"
        ];
        default = "code";
        description = ''
          Font feature profile for different use cases:
          • code: programming ligatures and stylistic sets
          • text: clean reading with basic ligatures
          • legacy: maximum compatibility, no features  
          • custom: user-defined via customFeatures
        '';
      };

      customFeatures = mkOption {
        type = types.listOf types.str;
        default = [
          "liga"
          "calt"
        ];
        description = "Custom OpenType features when featureProfile is 'custom'";
      };

      fallbacks = mkOption {
        type = types.listOf types.str;
        default = [
          "Noto Sans Mono"
          "DejaVu Sans Mono"
        ];
        description = "Fallback fonts for characters not available in primary font";
      };
    };

    # advanced terminal behaviors
    performance = {
      scrollbackLines = mkOption {
        type = types.int;
        default = 100000;
        description = "Terminal history depth - your digital memory buffer";
      };

      gpuAcceleration = mkOption {
        type = types.bool;
        default = true;
        description = "Enable GPU acceleration for smooth rendering";
      };

      vsync = mkOption {
        type = types.bool;
        default = true;
        description = "Enable vertical sync to prevent screen tearing";
      };
    };

    # wezterm-specific sophistication
    wezterm = {
      enable = mkEnableOption "WezTerm - the terminal for power users" // {
        default = true;
      };

      # custom cursor when aesthetic profile is "custom"
      cursor = {
        style = mkOption {
          type = types.enum [
            "BlinkingBlock"
            "SteadyBlock"
            "BlinkingUnderline"
            "SteadyUnderline"
            "BlinkingBar"
            "SteadyBar"
          ];
          default = "BlinkingBar";
          description = "Custom cursor style";
        };

        blinkRate = mkOption {
          type = types.int;
          default = 300;
          description = "Custom cursor blink rate in milliseconds";
        };
      };

      interface = {
        hideTabBarWhenSingle = mkOption {
          type = types.bool;
          default = true;
          description = "Hide tab bar when only one tab is open - clean aesthetic";
        };

        showTitleBar = mkOption {
          type = types.bool;
          default = false;
          description = "Show window title bar or use client-side decorations";
        };
      };
    };

    # ghostty-specific configuration
    ghostty = {
      enable = mkEnableOption "Ghostty - the modern terminal emulator" // {
        default = true;
      };

      wayland = {
        decoration = mkOption {
          type = types.bool;
          default = true;
          description = "Enable client-side decorations for Wayland integration";
        };

        singleInstance = mkOption {
          type = types.bool;
          default = true;
          description = "Use single instance mode for resource efficiency";
        };
      };
    };

    # shell integration preferences
    shell = {
      enableBashIntegration = mkOption {
        type = types.bool;
        default = true;
        description = "Enable bash shell integration for enhanced terminal features";
      };

      enableZshIntegration = mkOption {
        type = types.bool;
        default = true;
        description = "Enable zsh shell integration for enhanced terminal features";
      };
    };
  };

  config = mkIf cfg.enable (
    let
      # resolve aesthetic profiles to concrete values
      selectedCursor =
        if cfg.aesthetic.cursorProfile == "custom" then
          cfg.wezterm.cursor
        else
          cursorProfiles.${cfg.aesthetic.cursorProfile};

      selectedPadding = paddingProfiles.${cfg.aesthetic.paddingProfile};
      selectedFeatures = fontFeatures.${cfg.font.featureProfile};

    in
    {
      programs.wezterm = mkIf cfg.wezterm.enable {
        enable = true;
        inherit (cfg.shell) enableBashIntegration;

        extraConfig = ''
          local wezterm = require 'wezterm'
          local config = wezterm.config_builder()

          -- sophisticated cursor configuration
          config.default_cursor_style = '${selectedCursor.style}'
          ${optionalString (
            selectedCursor.blinkRate > 0
          ) "config.cursor_blink_rate = ${toString selectedCursor.blinkRate}"}

          -- advanced font configuration with fallbacks
          config.font = wezterm.font_with_fallback({
            '${cfg.font.family}',
            ${concatMapStrings (f: "    '${f}',\n") cfg.font.fallbacks}
          }, {weight='${cfg.font.weight}'})

          config.font_size = ${toString cfg.font.size}
          config.harfbuzz_features = {${concatMapStrings (f: "'${f}', ") selectedFeatures}}

          -- performance optimizations
          config.scrollback_lines = ${toString cfg.performance.scrollbackLines}
          ${optionalString cfg.performance.gpuAcceleration "config.webgpu_power_preference = 'HighPerformance'"}
          ${optionalString cfg.performance.vsync "config.enable_wayland = true"}

          -- aesthetic interface configuration
          config.hide_tab_bar_if_only_one_tab = ${boolToString cfg.wezterm.interface.hideTabBarWhenSingle}
          config.window_decorations = "${if cfg.wezterm.interface.showTitleBar then "TITLE" else "NONE"}"

          -- intelligent padding configuration
          config.window_padding = {
            left = ${toString selectedPadding},
            right = ${toString selectedPadding}, 
            top = ${toString selectedPadding},
            bottom = ${toString selectedPadding},
          }

          ${optionalString cfg.aesthetic.transparency.enable ''
            -- terminal transparency for desktop integration
            config.window_background_opacity = ${toString cfg.aesthetic.transparency.opacity}
          ''}

          return config
        '';
      };

      programs.ghostty = mkIf cfg.ghostty.enable {
        enable = true;
        inherit (cfg.shell) enableBashIntegration;

        settings =
          {
            # wayland integration
            window-decoration = cfg.ghostty.wayland.decoration;
            gtk-single-instance = cfg.ghostty.wayland.singleInstance;

            # sophisticated font configuration
            font-family = cfg.font.family;
            font-size = cfg.font.size;
            font-feature = selectedFeatures;

            # aesthetic padding
            window-padding-x = selectedPadding;
            window-padding-y = selectedPadding;

            # performance settings
            scrollback-lines = cfg.performance.scrollbackLines;

          }
          // (optionalAttrs cfg.aesthetic.transparency.enable {
            # transparency integration
            background-opacity = cfg.aesthetic.transparency.opacity;
          });
      };
    }
  );
}
