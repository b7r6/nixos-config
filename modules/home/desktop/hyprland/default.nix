{
  flake,
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.wayland.hyprland;
  inherit (flake) inputs;
in
{
  options.wayland.hyprland = {
    enable = mkEnableOption "Hyprland window manager";

    # Core components
    enableWaybar = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Waybar integration";
    };

    enableMako = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Mako notification daemon";
    };

    enableHy3 = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the hy3 plugin for tiling";
    };

    # Launchers
    launcher = mkOption {
      type = types.enum [
        "wofi"
        "rofi"
        "tofi"
        "fuzzel"
        "anyrun"
      ];
      default = "wofi";
      description = "Application launcher to use";
    };

    # Lock screen
    lockScreen = mkOption {
      type = types.enum [
        "swaylock"
        "swaylock-effects"
        "hyprlock"
      ];
      default = "swaylock";
      description = "Lock screen solution to use";
    };

    # Clipboard manager
    clipboardManager = mkOption {
      type = types.enum [
        "none"
        "cliphist"
        "copyq"
      ];
      default = "cliphist";
      description = "Clipboard manager to use";
    };

    # Screenshot tool
    screenshotTool = mkOption {
      type = types.enum [
        "grim+slurp"
        "swappy"
        "hyprshot"
        "grimblast"
      ];
      default = "grimblast";
      description = "Screenshot tool to use";
    };

    # Wallpaper
    wallpaperMode = mkOption {
      type = types.enum [
        "hyprpaper"
        "swww"
        "swaybg"
      ];
      default = "hyprpaper";
      description = "Wallpaper solution to use";
    };

    # Power management
    powerMenu = mkOption {
      type = types.enum [
        "none"
        "wlogout"
        "waylogout"
        "wleave"
      ];
      default = "wlogout";
      description = "Power menu to use";
    };

    # Idle management
    idleManager = mkOption {
      type = types.enum [
        "none"
        "swayidle"
        "hypridle"
      ];
      default = "swayidle";
      description = "Idle management solution";
    };

    # Default terminal
    terminal = mkOption {
      type = types.enum [
        "wezterm"
        "kitty"
        "alacritty"
        "foot"
      ];
      default = "wezterm";
      description = "Default terminal emulator";
    };

    # Default file manager
    fileManager = mkOption {
      type = types.enum [
        "dolphin"
        "thunar"
        "nemo"
        "nautilus"
      ];
      default = "dolphin";
      description = "Default file manager";
    };

    # Extras
    polkitAgent = mkOption {
      type = types.enum [
        "none"
        "polkit-kde-agent"
        "lxpolkit"
      ];
      default = "polkit-kde-agent";
      description = "Polkit authentication agent";
    };

    # Extras
    enableWlogout = mkOption {
      type = types.bool;
      default = false;
      description = "Enable wlogout for logout menu";
    };

    enableWlsunset = mkOption {
      type = types.bool;
      default = false;
      description = "Enable wlsunset for night light (blue light filter)";
    };

    # Animation settings
    animationStyle = mkOption {
      type = types.enum [
        "default"
        "minimal"
        "fancy"
        "none"
      ];
      default = "default";
      description = "Animation style preset";
    };

    # Custom configuration
    extraBinds = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional key bindings";
    };

    extraExecOnce = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional startup applications";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional packages to install";
    };
  };

  imports = [ inputs.hyprland.homeManagerModules.default ];

  config = mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = true;
      plugins = mkIf cfg.enableHy3 [ inputs.hy3.outputs.packages.${pkgs.stdenv.system}.hy3 ];
      settings = import ./settings.nix { inherit config lib cfg; };
    };

    # Waybar configuration
    programs.waybar = mkIf cfg.enableWaybar (import ./fancy-waybar.nix { inherit config; });

    # Lock screen configuration
    programs.swaylock = mkIf (cfg.lockScreen == "swaylock" || cfg.lockScreen == "swaylock-effects") (
      import ./swaylock.nix {
        inherit
          config
          lib
          cfg
          pkgs
          ;
      }
    );

    # Idle management using hypridle (via systemd user service)
    systemd.user.services = mkIf (cfg.idleManager == "hypridle") {
      hypridle = {
        Unit = {
          Description = "Hypridle daemon";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };

        Service = {
          ExecStart = "${inputs.hyprlang.packages.${pkgs.stdenv.system}.hypridle}/bin/hypridle";
          Restart = "on-failure";
        };

        Install = {
          WantedBy = [ "graphical-session.target" ];
        };
      };
    };

    # Configuration for hypridle
    home.file.".config/hypridle/hypridle.conf".text = mkIf (cfg.idleManager == "hypridle") (
      let
        lockCmd =
          if cfg.lockScreen == "swaylock" then
            "${pkgs.swaylock}/bin/swaylock"
          else if cfg.lockScreen == "swaylock-effects" then
            "${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --effect-blur 7x5"
          else if cfg.lockScreen == "hyprlock" then
            "${inputs.hyprlang.packages.${pkgs.stdenv.system}.hyprlock}/bin/hyprlock"
          else
            "${pkgs.swaylock}/bin/swaylock";
      in
      ''
        general {
          lock_cmd = ${lockCmd}
          before_sleep_cmd = ${lockCmd}
          after_sleep_cmd = hyprctl dispatch dpms on
        }

        listener {
          timeout = 300
          on-timeout = ${lockCmd}
        }

        listener {
          timeout = 380
          on-timeout = hyprctl dispatch dpms off
        }

        listener {
          name = reset-dpms
          timeout = 0
          on-resume = hyprctl dispatch dpms on
        }
      ''
    );
    services.swayidle = mkIf (cfg.idleManager == "swayidle") {
      enable = true;
      events = [
        {
          event = "before-sleep";
          command = "${cfg.lockScreen}";
        }
        {
          event = "lock";
          command = "${cfg.lockScreen}";
        }
      ];
      timeouts = [
        {
          timeout = 300;
          command = "${cfg.lockScreen}";
        }
        {
          timeout = 600;
          command = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
          resumeCommand = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
        }
      ];
    };

    # Power menu
    programs.wlogout = mkIf (cfg.powerMenu == "wlogout") (
      import ./wlogout.nix { inherit config lib cfg; }
    );

    # Notification daemon (mako)
    services.mako = mkIf cfg.enableMako (import ./mako.nix { inherit config lib cfg; });

    # Wallpaper
    services.hyprpaper = mkIf (cfg.wallpaperMode == "hyprpaper") (
      import ./hyprpaper.nix { inherit config lib cfg; }
    );

    # Base packages
    home.packages =
      with pkgs;
      [
        wl-clipboard
        pavucontrol
        xdg-utils

        # Terminal
        (lib.getAttr cfg.terminal {
          inherit wezterm;
          inherit kitty;
          inherit alacritty;
          inherit foot;
        })

        # File manager
        (lib.getAttr cfg.fileManager {
          inherit dolphin;
          inherit (xfce) thunar;
          inherit (cinnamon) nemo;
          inherit (gnome) nautilus;
        })

        # Screenshot tools
        (
          if cfg.screenshotTool == "grim+slurp" then
            [
              grim
              slurp
            ]
          else if cfg.screenshotTool == "swappy" then
            [
              grim
              slurp
              swappy
            ]
          else if cfg.screenshotTool == "hyprshot" then
            [ hyprshot ]
          else
            [ grimblast ]
        )

        # Launcher
        (lib.getAttr cfg.launcher {
          inherit wofi;
          rofi = rofi-wayland;
          inherit tofi;
          inherit fuzzel;
          inherit anyrun;
        })

        # Wallpaper
        (lib.getAttr cfg.wallpaperMode {
          inherit hyprpaper;
          inherit swww;
          inherit swaybg;
        })

        # Lock screen
        (lib.getAttr cfg.lockScreen {
          inherit swaylock;
          "swaylock-effects" = swaylock-effects;
          inherit (inputs.hyprlang.packages.${pkgs.stdenv.system}) hyprlock;
        })

        # Clipboard manager
        (
          if cfg.clipboardManager == "cliphist" then
            cliphist
          else if cfg.clipboardManager == "copyq" then
            copyq
          else
            null
        )

        # Polkit agent
        (
          if cfg.polkitAgent == "polkit-kde-agent" then
            libsForQt5.polkit-kde-agent
          else if cfg.polkitAgent == "lxpolkit" then
            lxde.lxpolkit
          else
            null
        )

        # Power menu
        (
          if cfg.powerMenu == "wlogout" then
            wlogout
          else if cfg.powerMenu == "waylogout" then
            waylogout
          else if cfg.powerMenu == "wleave" then
            wleave
          else
            null
        )

        # Idle manager
        (
          if cfg.idleManager == "swayidle" then
            swayidle
          else if cfg.idleManager == "hypridle" then
            inputs.hyprlang.packages.${pkgs.stdenv.system}.hypridle
          else
            null
        )

      ]
      ++ lib.optional cfg.enableWaybar waybar
      ++ lib.optional cfg.enableMako mako
      ++ lib.optional cfg.enableWlogout wlogout
      ++ lib.optional cfg.enableWlsunset wlsunset
      ++ cfg.extraPackages;

    # Wofi style
    home.file.".config/wofi/style.css".text = import ./wofi-style.nix { inherit config; };

    # Create a directory for default wallpaper just in case
    home.file.".config/hypr/.keep".text = "";
  };
}
