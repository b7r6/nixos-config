{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hypermodern.nixos.wayland;
in
{
  imports = [
    ./hyprland
  ];

  options.hypermodern.nixos.wayland = {
    enable = lib.mkEnableOption "// hypermodern // wayland // enable" // {
      default = false;
    };

    hyprland = {
      enable = lib.mkEnableOption "// hypermodern // hyprland // enable" // {
        default = true;
      };
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

    # xdg portal
    xdg.portal = {
      enable = true;
      xdgOpenUsePortal = true;

      extraPortals = with pkgs; [
        libsForQt5.xdg-desktop-portal-kde # TODO[b7r6]: consider plasma 6
        xdg-desktop-portal-wlr # wlroots for hyprland

        # TODO[b7r6]: figure out if we can live without it...
        # xdg-desktop-portal-gtk
      ];

      config = {
        common = {
          default = [ "kde" ]; # plasma is better

          "org.freedesktop.impl.portal.FileChooser" = [ "kde" ];
          "org.freedesktop.impl.portal.Settings" = [ "kde" ];
        };

        hyprland = {
          default = [
            "wlr"
            "kde"
          ]; # wlr for screenshots, kde for everything else
        };
      };
    };

    # portal services
    systemd.user.services = {
      xdg-desktop-portal-kde = {
        wantedBy = [ "graphical-session.target" ];
      };
    };

    environment.sessionVariables = {
      CLUTTER_BACKEND = "wayland";
      GDK_BACKEND = "wayland";
      MOZ_ENABLE_WAYLAND = "1";
      NIXOS_OZONE_WL = "1";
      QT_QPA_PLATFORM = "wayland";
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      SDL_VIDEODRIVER = "wayland";
      _JAVA_AWT_WM_NONREPARENTING = "1";

      # plasma already handles portals properly
      # GTK_USE_PORTAL = "1";
    };

    # n.b. it's 2025...
    services.xserver.enable = false;
  };
}
