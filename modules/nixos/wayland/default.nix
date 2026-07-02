# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                      // hyper-modern-nixos // nixos // wayland
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Consolidated Wayland + XDG Portal configuration for Hyprland
#
# Key design decisions:
#   - Use xdg-desktop-portal-hyprland (native), not xdg-desktop-portal-wlr
#   - Route Screenshot/ScreenCast/Inhibit to Hyprland portal
#   - Use GTK portal as fallback for file pickers, etc.
#   - Qt apps follow GTK theme via qt5ct/qt6ct
#   - Electron apps use native Wayland (NIXOS_OZONE_WL)
#
{
  pkgs,
  lib,
  config,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkAliasOptionModule
    types
    ;
  cfg = config.hyper-modern-nixos.wayland;
in
{
  imports = [
    # Backward compatibility: hyper-wayland -> wayland
    (mkAliasOptionModule [ "hyper-modern-nixos" "hyper-wayland" ] [ "hyper-modern-nixos" "wayland" ])
  ];

  options.hyper-modern-nixos.wayland = {
    enable = mkEnableOption "Wayland desktop with Hyprland portal support";

    qtTheme = mkOption {
      type = types.enum [
        "gtk2"
        "qt5ct"
        "qt6ct"
        "kvantum"
        "gnome"
      ];
      
      default = "qt5ct";
      
      description = ''
        Qt theming backend:
          gtk2    - Use GTK2 theme (simple, requires gtk2 theme installed)
          qt5ct   - Use qt5ct for Qt5/Qt6 theming (recommended)
          qt6ct   - Use qt6ct for Qt6 theming
          kvantum - Use Kvantum SVG theme engine
          gnome   - Use GNOME/Adwaita style
      '';
    };

    electronOzone = mkOption {
      type = types.bool;
      default = true;
      description = "Enable native Wayland for Electron apps";
    };
  };

  config = mkIf cfg.enable {

    # ── Core Wayland packages ──────────────────────────────────────────────────

    environment.systemPackages = with pkgs; [
      # Core utilities
      dbus
      dconf
      xdg-utils
      xdg-user-dirs
      glib
      wl-clipboard
      wl-clip-persist # Clipboard persistence after app closes
      cliphist # Clipboard history for wofi/rofi

      # Qt Wayland support
      qt6.qtwayland
      qt5.qtwayland # was libsForQt5.qt5.qtwayland; the nested .qt5 alias was removed
      kdePackages.qtwayland

      # Qt theming tools
      libsForQt5.qt5ct
      qt6Packages.qt6ct
      libsForQt5.qtstyleplugins # For gtk2 style

      # KDE/Plasma protocols (for portals and some apps)
      kdePackages.plasma-wayland-protocols

      # GTK support
      gtk3
      gtk4
      gsettings-desktop-schemas

      # Icon themes (ensure consistent icons)
      hicolor-icon-theme
      adwaita-icon-theme
      kdePackages.breeze-icons

      # Portal debugging
      xdg-desktop-portal
    ];

    # ── XDG Portal Configuration ───────────────────────────────────────────────

    #
    # Best practices for Hyprland:
    #   - Use xdg-desktop-portal-hyprland for Wayland-specific features
    #   - Use xdg-desktop-portal-gtk for file dialogs, app chooser, etc.
    #   - Do NOT use xdg-desktop-portal-wlr (generic wlroots, less features)
    #   - Do NOT enable wlr.enable (conflicts with hyprland portal)
    #

    xdg.portal = {
      enable = true;

      # Hyprland + GTK portals (order matters for fallback)
      extraPortals = with pkgs; [
        xdg-desktop-portal-hyprland
        xdg-desktop-portal-gtk
      ];

      # Explicit portal routing
      config = {
        # Common defaults (used when no desktop-specific config matches)
        common = {
          # GTK portal handles most things well
          default = [ "gtk" ];

          # File chooser - GTK provides nice native dialogs
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];

          # App chooser - GTK
          "org.freedesktop.impl.portal.AppChooser" = [ "gtk" ];
        };

        # Hyprland-specific overrides
        hyprland = {
          # Default to trying Hyprland first, then GTK
          default = [
            "hyprland"
            "gtk"
          ];

          # Screen capture MUST use Hyprland portal
          "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
          "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];

          # Session inhibit (prevent sleep during video, etc.)
          "org.freedesktop.impl.portal.Inhibit" = [ "hyprland" ];

          # Global shortcuts
          "org.freedesktop.impl.portal.GlobalShortcuts" = [ "hyprland" ];

          # File chooser still uses GTK (better UI)
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
          "org.freedesktop.impl.portal.AppChooser" = [ "gtk" ];

          # Secret storage
          "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
        };
      };

      # Use portal for xdg-open (consistent behavior)
      xdgOpenUsePortal = true;
    };

    # ── Environment Variables ──────────────────────────────────────────────────

    environment.sessionVariables = {

      # ── Wayland enforcement ──────────────────────────────────────────────────
      
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";
      XDG_SESSION_DESKTOP = "Hyprland";

      # ── Electron/Chromium ────────────────────────────────────────────────────
      
      NIXOS_OZONE_WL = if cfg.electronOzone then "1" else "0";
      ELECTRON_OZONE_PLATFORM_HINT = "auto"; # Let Electron auto-detect

      # ── Mozilla ──────────────────────────────────────────────────────────────
      
      MOZ_ENABLE_WAYLAND = "1";
      MOZ_DBUS_REMOTE = "1"; # Better Firefox integration

      # ── Java ─────────────────────────────────────────────────────────────────
      _JAVA_AWT_WM_NONREPARENTING = "1";
      AWT_TOOLKIT = "MToolkit"; # Better Java GUI support

      # ── Qt ───────────────────────────────────────────────────────────────────
      
      QT_QPA_PLATFORM = "wayland;xcb"; # Wayland preferred, X11 fallback
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      QT_QPA_PLATFORMTHEME = cfg.qtTheme;

      # ── GTK ──────────────────────────────────────────────────────────────────
      
      GDK_BACKEND = "wayland,x11"; # Wayland preferred, X11 fallback
      GTK_USE_PORTAL = "1"; # Use portal for file dialogs

      # ── SDL ──────────────────────────────────────────────────────────────────
      
      SDL_VIDEODRIVER = "wayland,x11"; # Wayland preferred, X11 fallback

      # ── Clutter ──────────────────────────────────────────────────────────────
      
      CLUTTER_BACKEND = "wayland";

      # ── Wine ──
      # WINEFSYNC = "1";  # Uncomment if using wine
    };

    # ── D-Bus ──────────────────────────────────────────────────────────────────

    services.dbus = {
      enable = true;

      # Use broker implementation (faster, more reliable)
      implementation = "broker";
    };

    # ── GNOME services for portal integration ──────────────────────────────────

    # GSettings/dconf (required for GTK apps to read settings)
    programs.dconf.enable = true;

    # GNOME keyring for secrets portal (also provides SSH agent via gcr)
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.login.enableGnomeKeyring = true;

    # Disable standard ssh-agent since gnome-keyring provides gcr-ssh-agent
    programs.ssh.startAgent = false;

    # ── Polkit (required for many desktop operations) ──────────────────────────

    security.polkit.enable = true;

    # GNOME polkit agent is more reliable than others
    systemd.user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };

    # ── XDG directories ────────────────────────────────────────────────────────

    xdg.mime.enable = true;

    # ── Disable X11 ────────────────────────────────────────────────────────────

    services.xserver.enable = lib.mkDefault false;

    # ── Fonts (ensure consistent rendering) ────────────────────────────────────

    fonts.fontconfig = {
      enable = true;
      antialias = true;

      hinting = {
        enable = true;
        autohint = false;
        style = "slight";
      };

      subpixel = {
        # For OLED, disable subpixel (it causes color fringing)
        rgba = "none";
        lcdfilter = "none";
      };
    };
  };
}
