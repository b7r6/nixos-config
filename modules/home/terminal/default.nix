{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.terminals;
  isLowEndHardware = cfg.lowEndHardware;
  hasStylex = config.stylix ? enable && config.stylix.enable;

  defaultFont = "Berkeley Mono";
  defaultFontSize = 12;

  defaultFontFeatures = [
    "liga"
    "calt"
    "ss01"
    "ss02"
    "ss03"
  ];
in
{
  options.terminals = {
    lowEndHardware = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to optimize for low-end hardware";
    };

    font = {
      name = mkOption {
        type = types.str;
        default = defaultFont;
        description = "Primary terminal font";
      };

      size = mkOption {
        type = types.int;
        default = defaultFontSize;
        description = "Font size for terminals";
      };

      features = mkOption {
        type = types.listOf types.str;
        default = defaultFontFeatures;
        description = "Font features to enable";
      };
    };

    padding = mkOption {
      type = types.int;
      default = 10;
      description = "Window padding for terminals";
    };
  };

  config = {

    programs.wezterm = {
      enable = true;
      enableBashIntegration = true;
      extraConfig = ''
        local wezterm = require 'wezterm'
        local config = {}
        if wezterm.config_builder then
          config = wezterm.config_builder()
        end

        -- Font configuration
        config.font = wezterm.font('${cfg.font.name}', {weight='DemiBold'})
        config.font_size = ${toString cfg.font.size}
        config.harfbuzz_features = {'${concatStringsSep "', '" cfg.font.features}'}

        -- UI configuration
        config.hide_tab_bar_if_only_one_tab = true

        config.window_padding = {
          left = ${toString cfg.padding},
          right = ${toString cfg.padding},
          top = ${toString cfg.padding},
          bottom = ${toString cfg.padding},
        }

        return config
      '';
    };

    # Alacritty configuration
    programs.alacritty = {
      enable = true;
      settings = {
        window = {
          padding = {
            x = cfg.padding;
            y = cfg.padding;
          };
          dynamic_padding = true;
        };

        font = {
          normal = {
            family = cfg.font.name;
            style = mkForce "SemiBold";
          };

          bold = {
            family = cfg.font.name;
            style = "Bold";
          };

          italic = {
            family = cfg.font.name;
            style = "SemiBold";
          };

          size = mkForce cfg.font.size;
        };

        general.live_config_reload = true;
      };
    };

    # Kitty configuration (only enabled on low-end hardware)
    programs.kitty = {
      enable = isLowEndHardware;

      settings = {
        font_family = cfg.font.name;
        bold_font = "${cfg.font.name} Bold";
        italic_font = "${cfg.font.name} Italic";
        bold_italic_font = "${cfg.font.name} Bold Italic";
        font_size = cfg.font.size;

        font_features = "${
          replaceStrings [ " " ] [ "-" ] cfg.font.name
        }-SemiBold +${concatStringsSep " +" cfg.font.features}";

        window_padding_width = cfg.padding;
        sync_to_monitor = true;
        disable_ligatures = if isLowEndHardware then "always" else "never";
        background_opacity = if hasStylex then "0.95" else "1.0";
      };
    };
  };
}
