{ config, lib, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.terminals;
in
{
  options.hyper-modern-nixos.terminals = {
    font = {
      name = mkOption {
        type = types.str;
        default = "Berkeley Mono";
        description = "primary terminal font";
      };

      weight = mkOption {
        type = types.str;
        default = "Regular";
        description = "primary terminal font weight";
      };

      size = mkOption {
        type = types.int;
        default = 12;
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

        -- cursor: blinking block, owned here at idle — same single-writer
        -- contract as ghostty (see the tmux config in modules/home/shell).
        -- n.b. wezterm blinks by *animating a fade* on the animation_fps
        -- budget, which defaults to 1 — a one-frame-per-second crossfade that
        -- itself reads as stutter. Constant easing makes blink a hard on/off.
        config.default_cursor_style = 'BlinkingBlock'
        config.cursor_blink_rate = 500
        config.cursor_blink_ease_in = 'Constant'
        config.cursor_blink_ease_out = 'Constant'

        -- font configuration
        config.font = wezterm.font('${cfg.font.name}', {weight='${cfg.font.weight}'})
        config.font_size = ${toString cfg.font.size}
        config.harfbuzz_features = {'${concatStringsSep "', '" cfg.font.features}'}

        -- ui
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

      settings = {
        # Force Wayland backend
        window-decoration = true; # Use client-side decorations
        gtk-single-instance = true;

        # Font settings to match your module
        font-family = "${cfg.font.name}";
        font-size = cfg.font.size;
        font-feature = cfg.font.features;

        # Cursor: blinking block, owned here at idle. Under the single-writer
        # contract (see the tmux config in modules/home/shell), the terminal's
        # own config is what rules when no app asserts a style — app DECSCUSR
        # (e.g. neovim's guicursor) overrides it, and a reset hands control
        # back here. `no-cursor` stops ghostty's shell integration from
        # asserting a bar at the prompt, which would make the shell a second
        # writer.
        cursor-style = "block";
        cursor-style-blink = true;
        shell-integration-features = "no-cursor";

        # Padding
        window-padding-x = cfg.padding;
        window-padding-y = cfg.padding;
      };
    };
  };
}
