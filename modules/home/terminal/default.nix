{ config, lib, ... }:
with lib;
let
  cfg = config.terminals;

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
  };
}
