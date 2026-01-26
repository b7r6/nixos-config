{
  pkgs,
  lib,
  config,
  ...
}:
with lib;
let
  cfg = config.hypermodern.wayland;
in
{
  options.hypermodern.wayland = {
    enable = mkEnableOption "hypermodern.wayland" // {
      default = false;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      dbus
      dconf
      xdg-utils
      qt6.qtwayland
      libsForQt5.qt5.qtwayland
      wl-clipboard
      hicolor-icon-theme
      adwaita-icon-theme
    ];

    # XDG portal configuration
    xdg.portal = {
      enable = true;
      wlr.enable = true;
      xdgOpenUsePortal = true;

      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-wlr
      ];

      config = {
        common = {
          default = [ "gtk" ];
        };
      };
    };

    # ensure portal services are enabled
    systemd.user.services = {
      xdg-desktop-portal-gtk = {
        wantedBy = [ "graphical-session.target" ];
      };
    };

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      _JAVA_AWT_WM_NONREPARENTING = "1";
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      GDK_BACKEND = "wayland";
      SDL_VIDEODRIVER = "wayland";
      CLUTTER_BACKEND = "wayland";
      # Force portal usage
      GTK_USE_PORTAL = "1";
    };

    services.xserver.enable = false;
  };
}
