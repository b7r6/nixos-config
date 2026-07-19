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
  themesCfg = config.hyper-modern-nixos.themes;

  # ── The wintermute contract ──────────────────────────────────────────────
  # The shell's ThemeService reads $XDG_STATE_HOME/wintermute/theme.json —
  # the durable output of the wintermute reconciler (continuity:
  # src/apps/wintermute). Nix SEEDS that file (and the theme.state control
  # file) from the computed theme system at activation, only if absent: the
  # provisioner writes the first generation, the daemon owns every one after.
  color-lib = import ../../flake/themes/lib.nix { inherit lib; };

  baseSlots = map (n: "base0${n}") [
    "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F"
  ];

  reg = cfg.register;
  facility = reg >= 0.5;

  seedThemeJson = pkgs.writeText "wintermute-theme.json" (
    builtins.toJSON {
      generation = 0;
      slug = themesCfg.resolved.slug or "legacy";
      polarity = themesCfg.polarity or "dark";
      heroHue = themesCfg.hero-hue;
      axisHue = themesCfg.axis-hue;
      register = reg;
      inherit facility;
      palette = lib.getAttrs baseSlots themesCfg.palette;
      tokens = {
        scanline = reg;
        bracketSize = reg;
        telemetryDensity = reg;
        glassBlur = 1.0 - reg;
        bloom = 1.0 - reg;
        grainOpacity = 1.0 - reg;
      };
      fontName = config.stylix.fonts.monospace.name;
    }
  );

  seedThemeState = pkgs.writeText "wintermute-theme.state" ''
    generation 0
    hero ${toString themesCfg.hero-hue}
    axis ${toString themesCfg.axis-hue}
    polarity ${themesCfg.polarity or "dark"}
    level ${themesCfg.level or "carbon"}
    ramp ${toString (themesCfg.ramp-hue or 211)}
    register ${toString (builtins.floor (reg * 1000))}
  '';

  # ── Corner previews ──────────────────────────────────────────────────────
  # The four corners of the preset space, computed by the SAME palette math
  # (lib.nix, pinned to the Lean generator by checks.ono-sendai-parity).
  cornerPreview = name: palette: light: {
    inherit name;
    palette = {
      background = palette.base00;
      accent = palette.base0A;
      success = palette.base0B;
      warning = palette.base0A;
      error = if light then "#c0392b" else "#f85149";
    };
  };

  presetsJson = pkgs.writeText "new-suzuki-presets.json" (
    builtins.toJSON {
      villa-straylight =
        cornerPreview "villa-straylight" (color-lib.make-palette { level = "carbon"; }) false;
      razorgirl = cornerPreview "razorgirl" (color-lib.make-palette { level = "carbon"; }) false;
      tessier =
        cornerPreview "tessier" (color-lib.make-palette-light { level = "tessier"; }) true;
      bioptic = cornerPreview "bioptic" (color-lib.make-palette-light {
        level = "neoform";
        ramp-hue = 36;
      }) true;
    }
  );

  # ── Shell QML Directory ──────────────────────────────────────────────────
  # The wallpaper shader compiles to Qt RHI bytecode (.qsb) at BUILD time —
  # no vendored binaries, the .frag source is the artifact under review.
  shellDir = pkgs.runCommand "new-suzuki-shell" {
    nativeBuildInputs = [ pkgs.qt6.qtshadertools ];
  } ''
    mkdir -p $out
    cp -r ${./shell}/* $out/
    cp ${presetsJson} $out/presets.json
    chmod -R u+w $out
    qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
      -o $out/modules/wallpaper/wallpaper.frag.qsb \
      $out/modules/wallpaper/wallpaper.frag
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

  azonixFont = pkgs.callPackage ./azonix.nix { };

  # The reconciler daemon/CLI from the continuity monorepo (theorem-carrying
  # core; the shell's ThemeService spawns `wintermute preset|set`).
  wintermute = flake.inputs.continuity.packages.${pkgs.system}.wintermute;
in
{
  options.hyper-modern-nixos.new-suzuki = {
    enable = mkEnableOption "New Suzuki Quickshell desktop shell";

    exclusive = mkOption {
      type = types.bool;
      default = false;
      description = ''
        When true, disables waybar/mako/wofi and takes over all keybinds.
      '';
    };

    register = mkOption {
      type = types.float;
      default = 1.0;
      description = ''
        Seed position on the affluent (0.0) ↔ facility (1.0) register axis.
        Only the FIRST generation — a running wintermute daemon owns the value
        afterwards. Default 1.0 = razorgirl (night-facility).
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
        ]
        ++ [
          azonixFont
          wintermute
          # Affluent-pole display serif (subset — google-fonts is enormous)
          (pkgs.google-fonts.override { fonts = [ "Cormorant Garamond" ]; })
        ];

      # ── Wintermute daemon ──────────────────────────────────────────────
      # The hot-reload control loop: watches theme.state, reconciles, pushes
      # to every live channel and rewrites theme.json for the shell. The
      # daemon is crash-only (adapters are best-effort by construction);
      # systemd supplies the uptime.
      systemd.user.services.wintermute = {
        Unit = {
          Description = "wintermute theme reconciler";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${wintermute}/bin/wintermute daemon";
          Restart = "always";
          RestartSec = 1;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # ── Font configuration ─────────────────────────────────────────────
      fonts.fontconfig.enable = true;

      # ── Cursor theme — capitaine-cursors: clean, modern, unobtrusive ─────
      # mkForce: the shell owns the cursor when enabled (desktop module sets
      # its own default otherwise).
      home.pointerCursor = lib.mkForce {
        package = pkgs.capitaine-cursors;
        name = "capitaine-cursors";
        size = 24;
        x11.enable = true;
        gtk.enable = true;
      };

      # ── Shell Config ──────────────────────────────────────────────────
      xdg.configFile."quickshell" = {
        source = shellDir;
        recursive = true;
      };

      # ── Wintermute state seed ──────────────────────────────────────────
      # Real files (not symlinks) in XDG_STATE, written only if absent —
      # the wintermute daemon/CLI atomically replaces them at runtime, so
      # Nix must never clobber a live generation. Stylix is the
      # provisioner; wintermute is the owner.
      home.activation.wintermuteSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _wm_dir="${config.xdg.stateHome}/wintermute"
        mkdir -p "$_wm_dir"
        if [ ! -f "$_wm_dir/theme.state" ]; then
          cp ${seedThemeState} "$_wm_dir/theme.state"
          chmod 644 "$_wm_dir/theme.state"
        fi
        if [ ! -f "$_wm_dir/theme.json" ]; then
          cp ${seedThemeJson} "$_wm_dir/theme.json"
          chmod 644 "$_wm_dir/theme.json"
        fi
      '';

      # ── Hyprland Autostart (non-exclusive) ─────────────────────────────
      hyper-modern-nixos.hyprland.autostart = lib.mkIf (!cfg.exclusive) [
        "env QT_QPA_PLATFORM=wayland QML_XHR_ALLOW_FILE_READ=1 quickshell -n"
      ];

      # ── Hyprland cursor config ─────────────────────────────────────────
      wayland.windowManager.hyprland.settings.exec-once = lib.mkAfter [
        "hyprctl setcursor capitaine-cursors 24"
      ];

      # ── Compositor glass ───────────────────────────────────────────────
      # Real backdrop blur for the shell's layer surfaces: the launcher gets
      # heavy glass, the bar a subtle one. ignorealpha keeps fully
      # transparent regions from blurring the whole screen.
      wayland.windowManager.hyprland.settings.layerrule = [
        "blur, qs_launcher"
        "ignorealpha 0.15, qs_launcher"
        "blur, qs_modules"
        "ignorealpha 0.25, qs_modules"
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
      # No hyprpaper: the shell's AnimatedWallpaper layer IS the wallpaper.
      # dbus-update-activation-environment MUST stay first: without it,
      # dbus-activated portal services (OpenURI — "click a link, nothing
      # happens" — Screenshot, FileChooser) and graphical-session units
      # never see WAYLAND_DISPLAY/XDG_CURRENT_DESKTOP.
      hyper-modern-nixos.hyprland.autostart = lib.mkForce [
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE"
        "blueman-applet"
        "nm-applet"
        "tailscale-systray"
        "env QT_QPA_PLATFORM=wayland QML_XHR_ALLOW_FILE_READ=1 quickshell -n"
      ];
    })
  ]);
}
