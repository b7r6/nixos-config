{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.wayland;
in
{
  options.hyper-modern-nixos.wayland = {
    enable = mkEnableOption "hyper-modern-nixos.wayland" // {
      default = false;
      description = "Enable the ultimate Wayland experience with ALL the features";
    };

    compositor = mkOption {
      type = types.enum [
        "sway"
        "hyprland"
        "river"
        "wayfire"
        "none"
      ];
      default = "none";
      description = "Which Wayland compositor you're rolling with";
    };

    screenShare = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable buttery smooth screen sharing via PipeWire";
      };

      preferredPortal = mkOption {
        type = types.enum [
          "wlr"
          "gtk"
          "kde"
          "hyprland"
        ];
        default = "wlr";
        description = "Portal backend for screen capture";
      };

      chromiumFlags = mkOption {
        type = types.bool;
        default = true;
        description = "Auto-configure Chromium-based browsers for Wayland screen sharing";
      };
    };

    audio = {
      lowLatency = mkOption {
        type = types.bool;
        default = false;
        description = "Enable low-latency audio for gaming/music production";
      };

      bluetooth = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Bluetooth audio with all codecs";
      };

      noiseSupression = mkOption {
        type = types.bool;
        default = false;
        description = "Enable AI noise suppression for microphones";
      };
    };

    performance = {
      gamingMode = mkOption {
        type = types.bool;
        default = false;
        description = "Optimize for gaming with GPU scheduling tweaks";
      };

      adaptiveSync = mkOption {
        type = types.bool;
        default = true;
        description = "Enable FreeSync/G-Sync support";
      };

      hwAcceleration = mkOption {
        type = types.bool;
        default = true;
        description = "Enable hardware video acceleration (VA-API/VDPAU)";
      };
    };

    eyeCandy = {
      animations = mkOption {
        type = types.bool;
        default = true;
        description = "Enable smooth animations and transitions";
      };

      transparencyEffects = mkOption {
        type = types.bool;
        default = true;
        description = "Enable blur and transparency effects";
      };

      cursors = {
        theme = mkOption {
          type = types.str;
          default = "Bibata-Modern-Ice";
          description = "Cursor theme to use";
        };

        size = mkOption {
          type = types.int;
          default = 24;
          description = "Cursor size in pixels";
        };
      };
    };

    compatibility = {
      xwaylandSupport = mkOption {
        type = types.bool;
        default = false;
        description = "Enable XWayland for legacy X11 apps (you said no xwayland but here's the option)";
      };

      electronApps = mkOption {
        type = types.bool;
        default = true;
        description = "Auto-configure Electron apps for Wayland";
      };

      javaFix = mkOption {
        type = types.bool;
        default = true;
        description = "Fix Java GUI apps on Wayland";
      };

      qt5Support = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Qt5 Wayland support";
      };

      qt6Support = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Qt6 Wayland support";
      };

      gtkTheme = mkOption {
        type = types.str;
        default = "Adwaita-dark";
        description = "GTK theme to use";
      };
    };

    tools = {
      clipboard = mkOption {
        type = types.bool;
        default = true;
        description = "Enable advanced clipboard management";
      };

      screenshots = mkOption {
        type = types.bool;
        default = true;
        description = "Enable screenshot tools (grim, slurp, swappy)";
      };

      colorPicker = mkOption {
        type = types.bool;
        default = true;
        description = "Enable color picker tools";
      };

      recorder = mkOption {
        type = types.bool;
        default = true;
        description = "Enable screen recording tools (wf-recorder)";
      };

      notifications = mkOption {
        type = types.bool;
        default = true;
        description = "Enable notification daemon (mako/dunst)";
      };
    };

    security = {
      lockscreen = mkOption {
        type = types.bool;
        default = true;
        description = "Enable swaylock/hyprlock";
      };

      idleManager = mkOption {
        type = types.bool;
        default = true;
        description = "Enable swayidle for power management";
      };

      polkit = mkOption {
        type = types.bool;
        default = true;
        description = "Enable polkit authentication agent";
      };

      sshAgent = mkOption {
        type = types.enum [ "gnome-keyring" "openssh" "none" ];
        default = "openssh";
        description = "SSH agent to use - gnome-keyring for desktop integration or openssh for standalone";
      };
    };
  };

  config = mkIf cfg.enable {
    # Core packages
    environment.systemPackages = with pkgs; [
      # Base Wayland stack
      dbus
      dconf
      xdg-utils
      wayland
      wayland-protocols
      wayland-utils
      seatd

      # Portal stuff
      xdg-desktop-portal
      xdg-desktop-portal-gtk
      xdg-desktop-portal-wlr

      # Qt support
      (mkIf cfg.compatibility.qt5Support libsForQt5.qt5.qtwayland)
      (mkIf cfg.compatibility.qt6Support qt6.qtwayland)

      # Clipboard
      (mkIf cfg.tools.clipboard wl-clipboard)
      (mkIf cfg.tools.clipboard clipman)
      (mkIf cfg.tools.clipboard wl-clip-persist)

      # Screenshot & recording tools
      (mkIf cfg.tools.screenshots grim)
      (mkIf cfg.tools.screenshots slurp)
      (mkIf cfg.tools.screenshots swappy)
      (mkIf cfg.tools.recorder wf-recorder)
      (mkIf cfg.tools.colorPicker hyprpicker)

      # Themes and cursors
      hicolor-icon-theme
      adwaita-icon-theme
      (mkIf (cfg.eyeCandy.cursors.theme == "Bibata-Modern-Ice") bibata-cursors)

      # Notifications
      (mkIf cfg.tools.notifications mako)
      (mkIf cfg.tools.notifications libnotify)

      # Security
      (mkIf cfg.security.lockscreen swaylock-effects)
      (mkIf cfg.security.idleManager swayidle)

      # Performance tools
      (mkIf cfg.performance.gamingMode gamemode)
      (mkIf cfg.performance.gamingMode mangohud)

      # Hardware acceleration
      (mkIf cfg.performance.hwAcceleration libva-utils)
      (mkIf cfg.performance.hwAcceleration vdpauinfo)

      # Audio tools
      pavucontrol
      pamixer
      (mkIf cfg.audio.bluetooth blueman)
      (mkIf cfg.audio.noiseSupression easyeffects)

      # Utilities
      wlr-randr
      wdisplays
      wlay
      waybar
      wofi
      bemenu
      fuzzel
      tofi
      wtype
      wev
      wlsunset
      kanshi
      brightnessctl
      playerctl
    ];

    # PipeWire configuration
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = cfg.audio.lowLatency;
      # wireplumber = {
      #   enable = true;
      #   configPackages = mkIf cfg.audio.lowLatency [
      #     (pkgs.writeTextDir "share/wireplumber/wireplumber.conf.d/99-lowlatency.conf" ''
      #       monitor.alsa.rules = [
      #         {
      #           matches = [
      #             { node.name = "~alsa_output.*" }
      #             { node.name = "~alsa_input.*" }
      #           ]
      #           actions = {
      #             update-props = {
      #               audio.rate = 48000
      #               audio.quantum = 128
      #               audio.min-quantum = 64
      #               audio.max-quantum = 256
      #             }
      #           }
      #         }
      #       ]
      #     '')
      #   ];
      # };
    };

    # Bluetooth audio codecs
    services.pipewire.wireplumber.configPackages = mkIf cfg.audio.bluetooth [
      (pkgs.writeTextDir "share/wireplumber/bluetooth.lua.d/51-bluez-config.lua" ''
        bluez_monitor.properties = {
          ["bluez5.enable-sbc-xq"] = true,
          ["bluez5.enable-msbc"] = true,
          ["bluez5.enable-hw-volume"] = true,
          ["bluez5.codecs"] = "[ sbc sbc_xq aac ldac aptx aptx_hd aptx_ll aptx_ll_duplex faststream faststream_duplex ]"
        }
      '')
    ];

    # Portal configuration
    xdg.portal = {
      enable = true;
      wlr.enable = cfg.screenShare.preferredPortal == "wlr";
      xdgOpenUsePortal = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        (mkIf (cfg.screenShare.preferredPortal == "wlr") xdg-desktop-portal-wlr)
        (mkIf (cfg.screenShare.preferredPortal == "hyprland") xdg-desktop-portal-hyprland)
        (mkIf (cfg.screenShare.preferredPortal == "kde") xdg-desktop-portal-kde)
      ];
      config = {
        common = {
          default = [
            cfg.screenShare.preferredPortal
            "gtk"
          ];
          "org.freedesktop.impl.portal.ScreenCast" = [ cfg.screenShare.preferredPortal ];
          "org.freedesktop.impl.portal.Screenshot" = [ cfg.screenShare.preferredPortal ];
        };
      };
    };

    # Security services
    security.polkit.enable = cfg.security.polkit;
    security.pam.services.swaylock = mkIf cfg.security.lockscreen { };
    services.dbus.enable = true;
    services.gvfs.enable = true;

    # SSH agent configuration
    services.gnome.gnome-keyring.enable = mkIf (cfg.security.sshAgent == "gnome-keyring") true;
    
    programs.ssh.startAgent = cfg.security.sshAgent == "openssh";

    # Environment variables
    environment.sessionVariables = {
      # Core Wayland
      NIXOS_OZONE_WL = "1";
      XDG_SESSION_TYPE = "wayland";
      XDG_CURRENT_DESKTOP = cfg.compositor;
      XDG_SESSION_DESKTOP = cfg.compositor;

      # Firefox
      MOZ_ENABLE_WAYLAND = "1";
      MOZ_USE_XINPUT2 = "1";

      # Qt
      QT_QPA_PLATFORM = "wayland;xcb";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";

      # GTK
      GDK_BACKEND = "wayland,x11";
      GTK_USE_PORTAL = "1";
      GTK_THEME = cfg.compatibility.gtkTheme;

      # Java
      _JAVA_AWT_WM_NONREPARENTING = mkIf cfg.compatibility.javaFix "1";

      # SDL
      SDL_VIDEODRIVER = "wayland";

      # Clutter
      CLUTTER_BACKEND = "wayland";

      # Elementary/EFL
      ECORE_EVAS_ENGINE = "wayland_egl";
      ELM_ENGINE = "wayland_egl";

      # Cursor
      XCURSOR_THEME = cfg.eyeCandy.cursors.theme;
      XCURSOR_SIZE = toString cfg.eyeCandy.cursors.size;

      # Hardware acceleration
      LIBVA_DRIVER_NAME = mkIf cfg.performance.hwAcceleration "radeonsi"; # or "i965" for Intel
      VDPAU_DRIVER = mkIf cfg.performance.hwAcceleration "radeonsi";

      # Gaming
      MANGOHUD = mkIf cfg.performance.gamingMode "1";
      ENABLE_VKBASALT = mkIf cfg.performance.gamingMode "1";

      # Electron apps
      ELECTRON_OZONE_PLATFORM_HINT = mkIf cfg.compatibility.electronApps "wayland";
    };

    # Chromium flags for screen sharing
    programs.chromium = mkIf cfg.screenShare.chromiumFlags {
      enable = true;
      extraOpts = {
        "EnableWebRtcPipeWireCapturer" = true;
      };
      extensions = [
        "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
        "cjpalhdlnbpafiamejdnhcphjbkeiagm" # uBlock Origin
      ];
    };

    # Disable X11
    services.xserver.enable = cfg.compatibility.xwaylandSupport;

    # Font configuration for better rendering
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-emoji
        liberation_ttf
        fira-code
        fira-code-symbols
        jetbrains-mono
        (nerdfonts.override {
          fonts = [
            "FiraCode"
            "JetBrainsMono"
          ];
        })
      ];

      fontconfig = {
        defaultFonts = {
          serif = [ "Noto Serif" ];
          sansSerif = [ "Noto Sans" ];
          monospace = [ "JetBrains Mono" ];
        };
      };
    };

    # Enable realtime scheduling for audio
    security.rtkit.enable = cfg.audio.lowLatency;
  };
}
