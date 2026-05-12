{ pkgs, ... }:
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
  ];

  # Enable all hyper-modern-nixos modules
  hyper-modern-nixos = {
    # impermanence.enable = true;

    # Theming - now with computed palettes!
    themes = {
      enable = true;

      # Use computed mode for dynamic palette generation
      mode = "computed";
      level = "night"; # L=8% - OLED safe
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
      enable = false;
      aws.enable = true;
      flyctl.enable = true;
      # Heavy toolchains - enable explicitly when needed:
      # gcp.enable = true;       # ~500MB
      # terraform.enable = true; # ~200MB
    };

    # Development environment
    dev = {
      enable = false;
      python.enable = true;
      typescript.enable = true;
      systems.enable = true;
      shell.enable = true;
      # Heavy toolchains - enable explicitly when needed:
      # dhall.enable = true;   # ~200MB
      # dotnet.enable = true;  # ~1GB
    };

    # LLM/AI tools
    llm.enable = false;

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
    vscode.enable = false;

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

      autostart = [
        "hyprpaper"
        "mako"
        "blueman-applet"
        "nm-applet"
        "tailscale-systray"
      ];

      windowRules = [
        {
          match = "class:^(brave|Brave)$";
          rules = [ "workspace 4" ];
        }
        {
          match = "class:^(firefox)$";
          rules = [ "workspace 5" ];
        }
        {
          match = "class:^(discord|Discord)$";
          rules = [ "workspace 6" ];
        }
        {
          match = "class:^(Spotify|spotify)$";
          rules = [ "workspace 10" ];
        }
      ];

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
      enable = false;
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

  home.packages = with pkgs; [
    dbus
    dconf
  ];
}
