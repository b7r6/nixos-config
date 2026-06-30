{
  flake,
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    mkMerge
    types
    ;

  cfg = config.hyper-modern-nixos.new-suzuki;

  # ── Initial palette ─────────────────────────────────────────────────────
  # The default preset is razorgirl (affluent × night). theme-switch can
  # change it at runtime; this is just the build-time fallback.
  presets = import ./presets.nix;
  initialPreset = presets.razorgirl;
  paletteJson = pkgs.writeText "new-suzuki-palette.json" (
    builtins.toJSON (
      initialPreset.tokens
      // {
        inherit (initialPreset)
          label
          family
          polarity
          luminance
          ;
        aesthetic = initialPreset.aesthetic;
        "font-name" = config.stylix.fonts.monospace.name;
      }
    )
  );

  # ── Shell QML Directory ──────────────────────────────────────────────────
  # NOTE: palette.json is NOT included here — it's written by theme-switch
  # at runtime. We provide an initial version via a separate xdg.configFile
  # that only fires if the file doesn't already exist (home-manager won't
  # clobber real files, only symlinks).
  shellDir = pkgs.runCommand "new-suzuki-shell" { } ''
    mkdir -p $out
    cp -r ${./shell}/* $out/
    # Don't include palette.json — it's managed at runtime by theme-switch
  '';

  # ── Quickshell global shortcut binds (appended in both modes) ─────────────
  quickshellBinds = [
    ", Print, global, quickshell:take_screenshot"
    "$mod SHIFT, E, global, quickshell:power_menu"
    "$mod SHIFT, V, global, quickshell:clipboard_history"
    ", XF86AudioRaiseVolume, global, quickshell:volume_up"
    ", XF86AudioLowerVolume, global, quickshell:volume_down"
    ", XF86AudioMute, global, quickshell:volume_mute"
    ", XF86MonBrightnessUp, global, quickshell:brightness_up"
    ", XF86MonBrightnessDown, global, quickshell:brightness_down"
  ];

  # ── Complete keybind replacement for exclusive mode ───────────────────────
  # Same hy3 semantics and navigation as the original, but shell components
  # (launcher, lockscreen) route through Quickshell's global dispatcher.
  # Screenshots go to quickshell's screenshot manager.
  exclusiveBinds = [
    # ── Core ────────────────────────────────────────────────────────────
    "$mod, Return, exec, ${config.hyper-modern-nixos.hyprland.apps.terminal}"
    "$mod, W, exec, ${config.hyper-modern-nixos.hyprland.apps.browser}"
    "$mod, Space, global, quickshell:app_launcher"
    "$mod, BackSpace, killactive"
    "$mod SHIFT, BackSpace, exit"
    "$mod SHIFT, L, global, quickshell:lock_screen"

    # ── Window States ───────────────────────────────────────────────────
    "$mod, F, fullscreen, 0"
    "$mod SHIFT, F, fullscreen, 1"
    "$mod, D, togglefloating"
    "$mod, P, pin"
    "$mod, C, centerwindow"

    # ── Navigation (vim preset + hy3) ───────────────────────────────────
    "$mod, H, hy3:movefocus, l"
    "$mod, L, hy3:movefocus, r"
    "$mod, K, hy3:movefocus, u"
    "$mod, J, hy3:movefocus, d"

    # ── Move Windows ────────────────────────────────────────────────────
    "$mod SHIFT, H, hy3:movewindow, l"
    "$mod SHIFT, L, hy3:movewindow, r"
    "$mod SHIFT, K, hy3:movewindow, u"
    "$mod SHIFT, J, hy3:movewindow, d"

    # ── Resize Windows ──────────────────────────────────────────────────
    "$mod ALT, H, resizeactive, -30 0"
    "$mod ALT, L, resizeactive, 30 0"
    "$mod ALT, K, resizeactive, 0 -30"
    "$mod ALT, J, resizeactive, 0 30"

    # ── Workspaces ──────────────────────────────────────────────────────
    "$mod, 1, workspace, 1"
    "$mod, 2, workspace, 2"
    "$mod, 3, workspace, 3"
    "$mod, 4, workspace, 4"
    "$mod, 5, workspace, 5"
    "$mod, 6, workspace, 6"
    "$mod, 7, workspace, 7"
    "$mod, 8, workspace, 8"
    "$mod, 9, workspace, 9"
    "$mod, 0, workspace, 10"

    "$mod SHIFT, 1, movetoworkspace, 1"
    "$mod SHIFT, 2, movetoworkspace, 2"
    "$mod SHIFT, 3, movetoworkspace, 3"
    "$mod SHIFT, 4, movetoworkspace, 4"
    "$mod SHIFT, 5, movetoworkspace, 5"
    "$mod SHIFT, 6, movetoworkspace, 6"
    "$mod SHIFT, 7, movetoworkspace, 7"
    "$mod SHIFT, 8, movetoworkspace, 8"
    "$mod SHIFT, 9, movetoworkspace, 9"
    "$mod SHIFT, 0, movetoworkspace, 10"

    # ── Workspaces 11-15 (right monitor) ───────────────────────────────
    "$mod CTRL, 1, workspace, 11"
    "$mod CTRL, 2, workspace, 12"
    "$mod CTRL, 3, workspace, 13"
    "$mod CTRL, 4, workspace, 14"
    "$mod CTRL, 5, workspace, 15"

    "$mod SHIFT CTRL, 1, movetoworkspace, 11"
    "$mod SHIFT CTRL, 2, movetoworkspace, 12"
    "$mod SHIFT CTRL, 3, movetoworkspace, 13"
    "$mod SHIFT CTRL, 4, movetoworkspace, 14"
    "$mod SHIFT CTRL, 5, movetoworkspace, 15"

    "$mod, Tab, workspace, m+1"
    "$mod SHIFT, Tab, workspace, m-1"

    # ── Monitor Controls ────────────────────────────────────────────────
    "$mod, comma, focusmonitor, -1"
    "$mod, period, focusmonitor, +1"
    "$mod SHIFT, comma, movewindow, mon:-1"
    "$mod SHIFT, period, movewindow, mon:+1"
    "$mod ALT, comma, movecurrentworkspacetomonitor, -1"
    "$mod ALT, period, movecurrentworkspacetomonitor, +1"
    "$mod ALT, S, swapactiveworkspaces, +1 current"

    # ── Screenshots (via quickshell) ────────────────────────────────────
    "$mod, S, global, quickshell:take_screenshot"

    # ── Media ───────────────────────────────────────────────────────────
    ", XF86AudioPlay, exec, playerctl play-pause"
    ", XF86AudioNext, exec, playerctl next"
    ", XF86AudioPrev, exec, playerctl previous"

    # ── hy3 Layout ──────────────────────────────────────────────────────
    "$mod, V, hy3:makegroup, v"
    "$mod, B, hy3:makegroup, h"
    "$mod, T, hy3:makegroup, tab"
    "$mod, G, hy3:changegroup, toggletab"
    "$mod, A, hy3:changefocus, raise"
    "$mod SHIFT, A, hy3:changefocus, lower"
    "$mod SHIFT, G, hy3:changegroup, opposite"

    # ── Preset Control Panel ───────────────────────────────────────────
    "$mod SHIFT, P, global, quickshell:control_panel"
  ];

  nierCursors = pkgs.callPackage ./nier-cursors.nix { };
  azonixFont = pkgs.callPackage ./azonix.nix { };
in
{
  imports = [ ./themes.nix ];

  options.hyper-modern-nixos.new-suzuki = {
    enable = mkEnableOption "New Suzuki Quickshell desktop shell";

    exclusive = mkOption {
      type = types.bool;
      default = false;
      description = ''
        When true, disables waybar/mako/wofi and takes over all keybinds.
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # ── Packages ──────────────────────────────────────────────────────
      home.packages =
        with pkgs;
        [
          quickshell
          cliphist
          wl-clipboard
          grim
          slurp
          brightnessctl
          pamixer
          playerctl
          nerd-fonts.symbols-only # Nerd Font icon glyphs for the vendored shell
          orbitron # geometric sci-fi display font
          phinger-cursors # angular monochrome cursor (fallback)
        ]
        ++ [
          nierCursors
          azonixFont
        ];

      # ── Font configuration ─────────────────────────────────────────────
      fonts.fontconfig.enable = true;

      # ── Cursor theme ───────────────────────────────────────────────────
      home.pointerCursor = {
        package = nierCursors;
        name = "NieR_Cursors";
        size = 24;
        x11.enable = true;
        gtk.enable = true;
      };

      # ── Shell Config ──────────────────────────────────────────────────
      xdg.configFile."quickshell" = {
        source = shellDir;
        recursive = true;
      };

      # ── Initial palette ────────────────────────────────────────────────
      # We write the initial palette.json as a real file (not a symlink)
      # via an activation script, so theme-switch can overwrite it later.
      # home-manager's xdg.configFile creates symlinks which conflict
      # with runtime writes, so we use home.activation instead.
      home.activation.newSuzukiPalette = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "${config.xdg.configHome}/quickshell/palette.json" ] || \
           [ -L "${config.xdg.configHome}/quickshell/palette.json" ]; then
          rm -f "${config.xdg.configHome}/quickshell/palette.json"
          cp ${paletteJson} "${config.xdg.configHome}/quickshell/palette.json"
          chmod 644 "${config.xdg.configHome}/quickshell/palette.json"
        fi
      '';

      # ── Hyprland Autostart (non-exclusive) ─────────────────────────────
      hyper-modern-nixos.hyprland.autostart = lib.mkIf (!cfg.exclusive) [
        "env QT_QPA_PLATFORM=wayland QML_XHR_ALLOW_FILE_READ=1 quickshell -n"
      ];

      # ── Hyprland cursor config ─────────────────────────────────────────
      wayland.windowManager.hyprland.settings.exec-once = lib.mkAfter [
        "hyprctl setcursor NieR_Cursors 24"
      ];
    }

    (mkIf cfg.exclusive {
      # ── Disable old shell components ───────────────────────────────────
      hyper-modern-nixos.waybar.enable = lib.mkForce false;
      hyper-modern-nixos.launchers.enable = lib.mkForce false;
      hyper-modern-nixos.notifications.enable = lib.mkForce false;

      # ── Replace the entire keybind list ────────────────────────────────
      # Same hy3 semantics + navigation as the original, but launcher/lock/
      # screenshot/volume/brightness route through Quickshell globals.
      wayland.windowManager.hyprland.settings.bind = lib.mkForce exclusiveBinds;

      # ── Autostart ──────────────────────────────────────────────────────
      hyper-modern-nixos.hyprland.autostart = lib.mkForce [
        "hyprpaper"
        "blueman-applet"
        "nm-applet"
        "tailscale-systray"
        "env QT_QPA_PLATFORM=wayland QML_XHR_ALLOW_FILE_READ=1 quickshell -n"
      ];
    })
  ]);
}
