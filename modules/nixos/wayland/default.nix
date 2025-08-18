{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.hyper-wayland;
in
{
  options.hyper-modern-nixos.hyper-wayland = {
    enable = mkEnableOption "hyper-modern-nixos.wayland" // {
      default = false;
    };
  };
  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Core utilities
      dbus
      dconf
      xdg-utils
      glib
      wl-clipboard
      # Qt/KDE support
      qt6.qtwayland
      libsForQt5.qt5.qtwayland
      kdePackages.qtwayland
      # Fixed: use kdePackages namespace
      kdePackages.plasma-wayland-protocols
      # GTK support
      gtk3
      gtk4
      gsettings-desktop-schemas
      # Icon themes
      hicolor-icon-theme
      adwaita-icon-theme
      kdePackages.breeze-icons
    ];
    # XDG portal configuration with proper config
    xdg.portal = {
      enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-hyprland
      ];
      # Address the warning about portal config
      config = {
        common = {
          default = "gtk";
          "org.freedesktop.impl.portal.Screenshot" = "hyprland";
          "org.freedesktop.impl.portal.ScreenCast" = "hyprland";
        };
      };
    };
    # Environment variables
    environment.sessionVariables = {
      # Wayland enforcement
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      _JAVA_AWT_WM_NONREPARENTING = "1"; # FIXED: underscore instead of asterisks
      # Qt configuration
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      # GTK configuration
      GDK_BACKEND = "wayland";
      # SDL/Gaming
      SDL_VIDEODRIVER = "wayland";
      # Clutter
      CLUTTER_BACKEND = "wayland";
      # Desktop environment
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";
    };
    # Enable dbus
    services.dbus.enable = true;
    # Ensure proper mime handling
    xdg.mime.enable = true;
    # GTK settings daemon
    programs.dconf.enable = true;
    # Disable X11
    services.xserver.enable = false;
    # Security
    security.polkit.enable = true;
  };
}
