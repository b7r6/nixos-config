{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.terminals;
  colors = config.hyper-modern-nixos.themes.palette;

  # base16 → ghostty theme lines (ANSI 0..15 the standard way). Shared shape
  # between the live sync (from theme.json) and the build-time seed below.
  ghosttySeed = pkgs.writeText "ghostty-wintermute-seed" ''
    background = ${colors.base00}
    foreground = ${colors.base05}
    cursor-color = ${colors.base0A}
    selection-background = ${colors.base02}
    selection-foreground = ${colors.base06}
    palette = 0=${colors.base00}
    palette = 1=${colors.base08}
    palette = 2=${colors.base0B}
    palette = 3=${colors.base0A}
    palette = 4=${colors.base0D}
    palette = 5=${colors.base0E}
    palette = 6=${colors.base0C}
    palette = 7=${colors.base05}
    palette = 8=${colors.base03}
    palette = 9=${colors.base08}
    palette = 10=${colors.base0B}
    palette = 11=${colors.base0A}
    palette = 12=${colors.base0D}
    palette = 13=${colors.base0E}
    palette = 14=${colors.base0C}
    palette = 15=${colors.base07}
  '';

  # ghostty's LIVE wintermute channel: read theme.json (wintermute's
  # authoritative palette, the same file emacs/nvim poll) → write the ghostty
  # theme → SIGUSR2 the running ghostty to retint. Driven by the systemd path
  # unit below; safe to run by hand.
  ghosttyThemeSync = pkgs.writeShellApplication {
    name = "ghostty-theme-sync";
    runtimeInputs = with pkgs; [ jq coreutils systemd procps ];
    text = ''
      tj="''${XDG_STATE_HOME:-$HOME/.local/state}/wintermute/theme.json"
      out="''${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/themes/wintermute"
      [ -r "$tj" ] || exit 0
      mkdir -p "$(dirname "$out")"
      tmp="$out.$$"
      if ! jq -r '.palette as $p |
        "background = \($p.base00)",
        "foreground = \($p.base05)",
        "cursor-color = \($p.base0A)",
        "selection-background = \($p.base02)",
        "selection-foreground = \($p.base06)",
        "palette = 0=\($p.base00)",  "palette = 8=\($p.base03)",
        "palette = 1=\($p.base08)",  "palette = 9=\($p.base08)",
        "palette = 2=\($p.base0B)",  "palette = 10=\($p.base0B)",
        "palette = 3=\($p.base0A)",  "palette = 11=\($p.base0A)",
        "palette = 4=\($p.base0D)",  "palette = 12=\($p.base0D)",
        "palette = 5=\($p.base0E)",  "palette = 13=\($p.base0E)",
        "palette = 6=\($p.base0C)",  "palette = 14=\($p.base0C)",
        "palette = 7=\($p.base05)",  "palette = 15=\($p.base07)"' "$tj" > "$tmp" 2>/dev/null; then
        rm -f "$tmp"; exit 0
      fi
      [ -s "$tmp" ] || { rm -f "$tmp"; exit 0; }
      mv -f "$tmp" "$out"
      systemctl --user reload app-com.mitchellh.ghostty.service 2>/dev/null \
        || pkill -USR2 -x ghostty 2>/dev/null || true
    '';
  };
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
        # Colours ride wintermute LIVE (see the sync + path unit below), not
        # stylix's frozen build-time palette. reload_config re-reads this theme.
        theme = "wintermute";

        # Font + opacity: disabling stylix.targets.ghostty (to take the theme)
        # ALSO dropped everything else stylix set here — the SemiBold weight, the
        # emoji fallback, the 14pt size and the terminal transparency. Restore
        # them from stylix's own font/opacity config so they stay coupled to it
        # (only COLOURS defect to wintermute).
        font-family = [
          config.stylix.fonts.monospace.name
          config.stylix.fonts.emoji.name
        ];
        font-size = config.stylix.fonts.sizes.terminal;
        font-feature = cfg.font.features;
        background-opacity = config.stylix.opacity.terminal;

        # Force Wayland backend
        window-decoration = true; # Use client-side decorations
        gtk-single-instance = true;

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

    # ── ghostty // wintermute live colour channel ──────────────────────────
    # stylix baked ghostty's palette at build time, so it drifted from every
    # wintermute reconcile. Turn that off and drive colours from theme.json:
    # a path unit watches the file, the sync writes the ghostty theme and
    # SIGUSR2s ghostty (ReloadSignal=SIGUSR2 in its own unit) to retint live.
    stylix.targets.ghostty.enable = false;

    systemd.user.services.ghostty-theme-sync = {
      Unit.Description = "Sync ghostty colours from wintermute theme.json";
      Service = {
        Type = "oneshot";
        ExecStart = "${ghosttyThemeSync}/bin/ghostty-theme-sync";
      };
    };
    systemd.user.paths.ghostty-theme-sync = {
      Unit.Description = "Watch wintermute theme.json for ghostty";
      Path.PathModified = "%h/.local/state/wintermute/theme.json";
      Install.WantedBy = [ "default.target" ];
    };

    # Seed the theme so `theme = wintermute` resolves before the first reconcile
    # — from the live theme.json if present, else the build-time palette.
    home.activation.ghosttyThemeSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${ghosttyThemeSync}/bin/ghostty-theme-sync || true
      _gt="${config.xdg.configHome}/ghostty/themes/wintermute"
      if [ ! -f "$_gt" ]; then
        run mkdir -p "$(dirname "$_gt")"
        run cp ${ghosttySeed} "$_gt"
      fi
    '';
  };
}
