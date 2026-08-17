{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.desktop;
in
{
  options.hyper-modern-nixos.desktop = {
    enable = lib.mkEnableOption "desktop applications and tools";

    browsers.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable web browsers (Firefox, Brave, Chromium)";
    };

    fileManager.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable file management (Nautilus + previews + archives)";
    };

    viewers.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Wayland-native viewers (images, PDF, video)";
    };

    utilities.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Daily-driver utilities (calculator, system monitor, disks, annotation, picker)";
    };

    audio.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable audio control tools (pwvucontrol)";
    };

    communication.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable communication apps (Slack, etc.)";
    };

    music.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable music production (Bitwig Studio)";
    };

    passwordManager.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 1Password GUI and CLI";
    };

    # ── Cursor theme (backported from new-suzuki) ────────────────────────────
    cursor = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable themed pointer cursor across GTK/Qt/X11";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.capitaine-cursors;
        description = "Cursor theme package";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "capitaine-cursors";
        description = "Cursor theme name as installed under share/icons";
      };

      size = lib.mkOption {
        type = lib.types.int;
        default = 32;
        description = "Cursor size in px (32 reads right on 4K at scale 1.0)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    fonts.fontconfig.enable = true;

    # ── Pointer cursor ───────────────────────────────────────────────────────
    # One coherent cursor across every toolkit. With hyprland rendering
    # software cursors (cursor:no_hardware_cursors, see the wayland module)
    # the themed pointer is exactly what reaches the glass. The setcursor
    # exec-once re-asserts theme+size inside hyprland itself, covering apps
    # that read the compositor's cursor rather than XCURSOR_* env.
    home.pointerCursor = lib.mkIf cfg.cursor.enable {
      inherit (cfg.cursor) package name size;
      x11.enable = true;
      gtk.enable = true;
    };

    wayland.windowManager.hyprland.settings.exec-once = lib.mkIf cfg.cursor.enable (
      lib.mkAfter [ "hyprctl setcursor ${cfg.cursor.name} ${toString cfg.cursor.size}" ]
    );

    home.packages =
      with pkgs;
      lib.flatten [
        (lib.optionals cfg.passwordManager.enable [
          _1password-cli
          _1password-gui-beta
        ])

        (lib.optionals cfg.browsers.enable [
          brave
          chromium
          firefox
        ])

        # Files: nautilus (GTK4, portal-integrated) + space-bar previews +
        # archives. nemo retires with the rest of the GTK3 era.
        (lib.optionals cfg.fileManager.enable [
          nautilus
          sushi
          file-roller
        ])

        # Viewers — wayland-native GTK4; all follow the portal color-scheme,
        # so wintermute's day/night flip reaches every one of them live.
        (lib.optionals cfg.viewers.enable [
          loupe # images
          papers # PDF (the evince successor)
          celluloid # video (mpv frontend)
          mpv
        ])

        # pipewire-native mixer (pavucontrol retired)
        (lib.optional cfg.audio.enable pwvucontrol)

        # Daily-driver utilities
        (lib.optionals cfg.utilities.enable [
          qalculate-gtk # THE calculator; qalc also powers the launcher's = mode
          libqalculate
          mission-center # system monitor with real GPU telemetry
          gnome-disk-utility
          satty # screenshot annotation, made for grim/slurp flows
          hyprpicker # color picker
        ])

        # Bitwig only ships x86_64-linux binaries (its ARM builds are
        # Windows-only), so gate on the package's full capability set
        # (platforms/badPlatforms via availableOn) rather than hard-coding an
        # architecture: aarch64 hosts like shimmer skip it cleanly today and
        # pick it up automatically if upstream ever ships arm64.
        (lib.optional (
          cfg.music.enable && lib.meta.availableOn pkgs.stdenv.hostPlatform bitwig-studio
        ) bitwig-studio)

        (lib.optionals cfg.communication.enable (
          [
            slack-term
            spotify-cli-linux
            telegram-desktop
          ]
          # Slack's Electron desktop app has no aarch64-linux build in nixpkgs
          # (x86_64-linux + darwin only), and an unavailable package in the
          # closure breaks the whole home generation on aarch64 hosts like the
          # DGX Spark (shimmer). Gate it to the architecture that can build it.
          ++ lib.optional pkgs.stdenv.hostPlatform.isx86_64 slack
        ))
      ];
  };
}
