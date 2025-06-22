{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.terminals;
in
{
  options.hyper-modern-nixos.terminals = {
    font = {
      name = mkOption {
        type = types.str;
        default = "Berkeley Mono SemiBold";
        description = "primary terminal font";
      };

      size = mkOption {
        type = types.int;
        default = 14;
        description = "font size for terminals";
      };

      features = mkOption {
        type = types.listOf types.str;
        default = [
          "liga"
          "calt"
          "ss01"
          "ss02"
          "ss03"
        ];
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

    programs.ghostty = {
      enable = true;
      enableBashIntegration = true;
    };
  };
}
