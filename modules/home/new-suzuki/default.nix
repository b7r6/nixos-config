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
    "0"
    "1"
    "2"
    "3"
    "4"
    "5"
    "6"
    "7"
    "8"
    "9"
    "A"
    "B"
    "C"
    "D"
    "E"
    "F"
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
      villa-straylight = cornerPreview "villa-straylight" (color-lib.make-palette {
        level = "carbon";
      }) false;
      razorgirl = cornerPreview "razorgirl" (color-lib.make-palette { level = "carbon"; }) false;
      tessier = cornerPreview "tessier" (color-lib.make-palette-light { level = "tessier"; }) true;
      bioptic = cornerPreview "bioptic" (color-lib.make-palette-light {
        level = "neoform";
        ramp-hue = 36;
      }) true;
    }
  );

  # ── Shell QML Directory ──────────────────────────────────────────────────
  # The wallpaper shader compiles to Qt RHI bytecode (.qsb) at BUILD time —
  # no vendored binaries, the .frag source is the artifact under review.
  shellDir = pkgs.runCommand "new-suzuki-shell" { nativeBuildInputs = [ pkgs.qt6.qtshadertools ]; } ''
    mkdir -p $out
    cp -r ${./shell}/* $out/
    cp ${presetsJson} $out/presets.json
    chmod -R u+w $out
    qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
      -o $out/modules/wallpaper/wallpaper.frag.qsb \
      $out/modules/wallpaper/wallpaper.frag
  '';

  # ── Quickshell global shortcut binds (appended in both modes) ─────────────

  # ── Complete keybind replacement for exclusive mode ───────────────────────
  # Same hy3 semantics and navigation as the original, but shell components
  # (launcher, lockscreen) route through Quickshell's global dispatcher.
  # Direct screenshot chords keep the original grimblast behavior, while
  # bare Print routes through Quickshell's screenshot manager.
  exclusiveBinds = [
    # ── Core ────────────────────────────────────────────────────────────
    "$mod, Return, exec, ${config.hyper-modern-nixos.hyprland.apps.terminal}"
    "$mod, W, exec, ${config.hyper-modern-nixos.hyprland.apps.browser}"
    "$mod, Space, global, quickshell:app_launcher"
    "$mod, BackSpace, killactive"
    "$mod SHIFT, BackSpace, exit"
    "$mod SHIFT, L, global, quickshell:lock_screen"

    # ── The C-M-{n,p} gesture, one layer up: Super+Ctrl+n/p cycles
    #    compositor windows — same shape as emacs forward/backward-list,
    #    modifier picks the layer. (C-M-n itself passes through zellij
    #    untouched and stays emacs's.) ──────────────────────────────────
    "$mod CTRL, N, cyclenext,"
    "$mod CTRL, P, cyclenext, prev"

    # ── Alpha scrub: Alt+wheel dials the focused window's transparency,
    #    Alt+middle-click resets to solid ────────────────────────────────
    "ALT, mouse_down, exec, wm-alpha down"
    "ALT, mouse_up, exec, wm-alpha up"
    "ALT, mouse:274, exec, wm-alpha reset"

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

    # ── Screenshots ─────────────────────────────────────────────────────
    # Preserve the pre-New-Suzuki muscle memory for immediate captures.
    # Bare Print still opens Quickshell's richer region/window/screen picker.
    ", Print, global, quickshell:take_screenshot"
    "$mod, S, exec, grimblast copy area"
    "$mod SHIFT, S, exec, grimblast save area ~/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png"
    "$mod SHIFT ALT, S, exec, grimblast copy screen"

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

  # Per-window alpha scrub (Alt+wheel). hyprctl setprop alpha is a live
  # multiplier on top of the normal active/inactive opacity; we track the
  # current value per window address in XDG_RUNTIME_DIR since hyprland
  # doesn't read props back. Clamped to [0.25, 1.0].
  wm-alpha = pkgs.writeShellScriptBin "wm-alpha" ''
    addr=$(${pkgs.hyprland}/bin/hyprctl activewindow -j | ${pkgs.jq}/bin/jq -r .address)
    [ -z "$addr" ] || [ "$addr" = "null" ] && exit 0
    dir="''${XDG_RUNTIME_DIR:-/tmp}/wm-alpha"
    mkdir -p "$dir"
    f="$dir/$addr"
    cur=$(cat "$f" 2>/dev/null || echo 1.0)
    case "$1" in
      down)  new=$(${pkgs.gawk}/bin/awk -v c="$cur" 'BEGIN{n=c-0.05; if(n<0.25)n=0.25; printf "%.2f", n}') ;;
      up)    new=$(${pkgs.gawk}/bin/awk -v c="$cur" 'BEGIN{n=c+0.05; if(n>1.0)n=1.0; printf "%.2f", n}') ;;
      reset) new=1.00 ;;
      *)     exit 1 ;;
    esac
    ${pkgs.hyprland}/bin/hyprctl setprop "address:$addr" alpha "$new" > /dev/null
    echo "$new" > "$f"
  '';

  # The reconciler daemon/CLI from the continuity monorepo (theorem-carrying
  # core; the shell's ThemeService spawns `wintermute preset|set`).
  wintermute = flake.inputs.wintermute.packages.${pkgs.stdenv.hostPlatform.system}.wintermute;

  # The wallpaper field as a CUDA kernel (straylight-nvidia-sdk) — CLI plus
  # the zero-copy wayland presenter. Built against the SDK's own toolchain;
  # autoAddDriverRunpath in its default.nix resolves the real libcuda.
  wintermuteField =
    pkgs.callPackage "${flake.inputs.straylight-nvidia-sdk}/examples/wintermute-field"
      { cuda = flake.inputs.straylight-nvidia-sdk.packages.${pkgs.stdenv.hostPlatform.system}.cuda; };

  # Daemon launcher: graphical-session units usually inherit WAYLAND_DISPLAY
  # via dbus-update-activation-environment --systemd, but that races the
  # target going up — discover the socket ourselves if it lost.
  wintermuteFieldLauncher = pkgs.writeShellScript "wintermute-field-launch" ''
    if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
      WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -m1 '^wayland-[0-9]*$' || true)
      export WAYLAND_DISPLAY
    fi
    exec ${wintermuteField}/bin/wintermute-field-daemon --scene ${cfg.cudaField.scene}
  '';

  quickshellLaunch =
    "env QT_QPA_PLATFORM=wayland QML_XHR_ALLOW_FILE_READ=1"
    + lib.optionalString cfg.cudaField.enable " HYPERMODERN_CUDA_FIELD=1"
    + " quickshell -n";
in
{
  options.hyper-modern-nixos.new-suzuki = {
    enable = mkEnableOption "New Suzuki Quickshell desktop shell";

    exclusive = mkOption {
      type = types.bool;
      default = false;
      description = ''
        When true, the shell owns the bar/launcher/notification surfaces
        outright and takes over all keybinds.
      '';
    };

    cudaField = {
      enable = lib.mkEnableOption ''
        the CUDA wallpaper presenter: wintermute-field-daemon renders the
        field into the compositor's wl_shm pool (zero-copy on GB10) and the
        QML AnimatedWallpaper stands down (HYPERMODERN_CUDA_FIELD=1)
      '';

      scene = mkOption {
        type = types.enum [
          "field"
          "eyes"
        ];
        default = "field";
        description = ''
          Which card the kernel renders: "field" is the two-axis design
          space, "eyes" the reference-reel title card (plasma blades, the
          CASK6 kernel words, the smeared floor). A "scene" key in
          theme.json overrides this live.
        '';
      };
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
          wm-alpha
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
          # No start-limit ceiling — parity with wintermute-field. A SIGKILL
          # FLOOD (kill -9 in a tight loop) otherwise trips systemd's default
          # 5-starts-per-10s ratelimiter, after which Restart=always AND
          # Upholds= both back off ("tried this too often recently") and the
          # unit wedges dead. The field survived exactly this because it
          # already carried the line; the reconciler didn't, and a flood
          # beheaded it. Interval 0 disables the limiter: every kill is
          # answered by a restart within RestartSec, forever, no matter the
          # rate. The daemon is level-triggered and cheap — respawning is free.
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = "${wintermute}/bin/wintermute daemon";
          Restart = "always";
          RestartSec = 1;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # ── CUDA field presenter (optional) ────────────────────────────────
      # The wallpaper as a kernel: zero-copy into the compositor's pool on
      # GB10, frame-callback paced (occluded = parked at 0% GPU), watches
      # theme.json and fires the reconcile sweep on generation bumps.
      systemd.user.services.wintermute-field = lib.mkIf cfg.cudaField.enable {
        Unit = {
          Description = "wintermute-field — CUDA wallpaper presenter";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
          # Never give up on the wallpaper: no start-limit ceiling, so even a
          # burst of surface-closes (an output-reconfiguration storm during
          # login) can't trip systemd's rate limiter and wedge the desktop
          # blank. The daemon is cheap to respawn.
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = "${wintermuteFieldLauncher}";
          # Restart=always, NOT on-failure: the daemon exits CLEANLY (status 0)
          # when the compositor closes its background layer surface — which
          # Hyprland does during output reconfiguration (session startup, an
          # interactive login, monitor/DPMS events). With on-failure a clean
          # exit never restarts, so the QML wallpaper (which has already stood
          # down via HYPERMODERN_CUDA_FIELD=1) leaves a BLANK desktop. always
          # self-heals: the fresh process recreates the surface. ~1s to respawn.
          Restart = "always";
          RestartSec = 1;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # ── The keeper: level-triggered liveness for the wallpaper stack ─────
      # Restart=always self-heals crashes and clean exits, but an EXPLICIT
      # `systemctl --user stop` (observed in the wild: fleet automation with
      # ssh reach reaping the units, eight confirmed kills) is honored by
      # systemd as intent and never restarted. The declared state is ON, so
      # a keeper timer converges to it: every 30s, start whatever is down.
      # `start` on a running unit is a no-op — the keeper is silent unless
      # something actually died. To INTENTIONALLY stop the wallpaper, stop
      # the keeper timer first.
      systemd.user.services.wintermute-keeper = lib.mkIf cfg.cudaField.enable {
        Unit.Description = "wintermute keeper — converge theme stack to ON";
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "wintermute-keep" ''
            ${pkgs.systemd}/bin/systemctl --user start wintermute.service wintermute-field.service
          ''}";
        };
      };
      systemd.user.timers.wintermute-keeper = lib.mkIf cfg.cudaField.enable {
        Unit.Description = "wintermute keeper tick";
        Timer = {
          OnActiveSec = "30s";
          OnUnitActiveSec = "30s";
          AccuracySec = "5s";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # ── Upholds: the session itself enforces the stack ───────────────────
      # The keeper timer can be stopped like anything else (chaos test 5:
      # behead the keeper, then the stack — stays dead). Upholds= is the
      # systemd primitive built for this: as long as the UPHOLDER is active,
      # the upheld units are continuously restarted, explicit stops included.
      # The upholder here is graphical-session.target — stopping THAT means
      # ending the login session, which is no longer a wallpaper prank. The
      # keeper timer stays as defense-in-depth (and heals post-reload races).
      # Intentional off-switch: `systemctl --user stop graphical-session.target`
      # is logout; short of that, edit this module — which is the point.
      xdg.configFile."systemd/user/graphical-session.target.d/10-wintermute-upholds.conf" =
        lib.mkIf cfg.cudaField.enable
          {
            text = ''
              [Unit]
              Upholds=wintermute.service wintermute-field.service wintermute-keeper.timer
            '';
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
      hyper-modern-nixos.hyprland.autostart = lib.mkIf (!cfg.exclusive) [ quickshellLaunch ];

      # ── Hyprland cursor config ─────────────────────────────────────────
      wayland.windowManager.hyprland.settings.exec-once = lib.mkAfter [
        "hyprctl setcursor capitaine-cursors 24"
      ];

      # ── Compositor glass ───────────────────────────────────────────────
      # Real backdrop blur for the shell's layer surfaces: the launcher gets
      # heavy glass, the bar a subtle one. ignore_alpha keeps fully
      # transparent regions from blurring the whole screen.
      #
      # Syntax note: this Hyprland (0.55, Desktop::Rule engine) takes rules
      # as comma-separated `effect value` / `match:prop value` pairs —
      # grammar read from src/desktop/rule/ and every line verified `ok`
      # against the live compositor via `hyprctl keyword`.
      wayland.windowManager.hyprland.settings.layerrule = [
        "blur 1, match:namespace qs_launcher"
        "ignore_alpha 0.15, match:namespace qs_launcher"
        "blur 1, match:namespace qs_modules"
        "ignore_alpha 0.25, match:namespace qs_modules"
        "blur 1, match:namespace qs_control_panel"
        "ignore_alpha 0.15, match:namespace qs_control_panel"
      ];

      # Floating windows live in the glass: noticeably translucent (blur
      # carries legibility), snapping solid when focused enough to read.
      # (windowrulev2 is deprecated; the prop is `float`, not `floating`.)
      wayland.windowManager.hyprland.settings.windowrule = lib.mkAfter [
        "opacity 0.92 0.78, match:float 1"
      ];
    }

    (mkIf cfg.exclusive {
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
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE SSH_AUTH_SOCK"
        "blueman-applet"
        "nm-applet"
        "tailscale-systray"
        quickshellLaunch
      ];
    })
  ]);
}
