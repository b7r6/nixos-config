{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    # user identity
    ./me.nix

    # baseline toolchain presets
    ./cloud
    ./dev
    ./llm
    ./nix

    # terminal tooling
    ./emacs
    ./neovim
    ./shell
    ./terminal
    ./themes

    # session management
    ./desktop
    ./session
    ./wayland
    ./vscode

    # quickshell desktop shell (default off; exclusive mode replaces
    # waybar/wofi/mako wholesale)
    ./new-suzuki
  ];

  # enable all hyper-modern-nixos modules...
  hyper-modern-nixos = {
    # impermanence.enable = true;

    # theming - now with computed palettes...
    themes = {
      enable = true;

      # Use computed mode for dynamic palette generation.
      # Default theme: ono-sendai-sprawl == computed at the `carbon` level.
      mode = "computed";
      level = "carbon"; # L=11% - the "sprawl" level
      hero-hue = 211; # Classic ono-sendai blue
      axis-hue = 201; # Cool shift for variables

      # Or use legacy mode for pre-baked palettes:
      # mode = "legacy";
      # theme = "ono-sendai";
      # variant = "razorgirl";

      # Display config is per-host (set in configurations/nixos/<host>/configuration.nix)
      overrides = {
        fontSizes = {
          desktop = 16;
          applications = 14;
          terminal = 14;
          popups = 14;
        };
      };
    };

    # Cloud tools (AWS enabled by default, heavy ones disabled)
    cloud = {
      enable = true;
      aws.enable = true;
      flyctl.enable = true;

      # rclone on PATH machine-wide, with the `straylight-r2` remote deployed
      # from the rclone-conf agenix secret to ~/.config/rclone/rclone.conf.
      rclone.enable = true;

      # Heavy toolchains - enable explicitly when needed:
      # gcp.enable = true;       # ~500MB
      # terraform.enable = true; # ~200MB
    };

    # Development environment
    dev = {
      enable = true;
      python.enable = true;
      typescript.enable = true;
      systems.enable = true;
      shell.enable = true;

      # Heavy toolchains - enable explicitly when needed:
      dhall.enable = true; # ~200MB
      # dotnet.enable = true;  # ~1GB
    };

    # LLM/AI tools
    llm.enable = true;

    # Nix development
    nix.enable = true;

    # Shell configuration
    shell.enable = true;

    # Editors
    emacs = {
      enable = true;
      seedConfig = true;
      rust.enable = true;

      # Heavy language servers - enable explicitly when needed:
      # haskell.enable = true;  # ~1GB
      # lean4.enable = true;    # ~500MB
    };

    neovim.enable = true;
    vscode.enable = true;

    # Session management
    session.enable = true;

    # Desktop applications
    desktop.enable = true;

    # ── Hyprland Window Manager ───────────────────────────────────────────────

    # Monitor config is per-host (set in configurations/nixos/<host>/configuration.nix)

    hyprland = {
      enable = true;

      apps = {
        terminal = "ghostty";
        launcher = "wofi --show drun";
        browser = "firefox";
        fileManager = "nemo";
        lockScreen = "swaylock";
      };

      appearance = {
        gaps = {
          inner = 4;
          outer = 8;
        };

        border = {
          size = 2;
          radius = 0;
        };

        opacity = {
          active = 1.0;
          inactive = 0.85;
        };

        blur = {
          enable = true;
          size = 8;
          passes = 2;
        };

        animations = {
          enable = true;
          speed = "fast";
        };
      };

      input = {
        keyboard = {
          layout = "us";
          options = "ctrl:nocaps";
        };

        mouse = {
          sensitivity = 0.0;
          accelProfile = "flat";
        };

        touchpad = {
          naturalScroll = true;
          tapToClick = true;
        };
      };

      keybindings = {
        preset = "vim";
        mod = "SUPER";
      };

      # session daemons only — tray applets come from hyprland.systray toggles
      autostart = [
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE"
        "hyprpaper"
        "mako"
      ];

      windowRules = [ ];

      plugins.hy3.enable = true;
    };

    # ── Supporting Tools ──────────────────────────────────────────────────────

    waybar = {
      enable = true;
      position = "top";
      height = 30;
      modules = {
        left = [
          "hyprland/workspaces"
          "hyprland/mode"
        ];
        center = [ "hyprland/window" ];
        right = [
          "pulseaudio"
          "network"
          "cpu"
          "memory"
          "clock"
          "tray"
        ];
      };
    };

    launchers = {
      enable = true;
      default = "wofi";

      wofi = {
        enable = true;
        width = 600;
        height = 450;
      };

      rofi.enable = true;
    };

    notifications = {
      enable = true;
      position = "top-right";
      timeout = 5000;
      width = 350;
    };

    lockscreen = {
      enable = true;
      indicatorRadius = 100;
      showFailedAttempts = true;
    };
  };

  # Wayland (backward compatibility flag)
  wayland.enable = true;

  # Sensible default for home.homeDirectory (previously supplied by
  # nixos-unified's homeModules.common). home.username comes from me.nix.
  # Under NixOS home-manager (useUserPackages), the host sets this; standalone
  # `nh home switch` relies on this default.
  home.homeDirectory = lib.mkDefault "/home/${config.home.username}";

  home.packages = with pkgs; [
    dbus
    dconf
  ];
}
