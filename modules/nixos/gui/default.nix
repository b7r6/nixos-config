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
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      dbus
      dconf
      xdg-utils
      qt6.qtwayland
      wl-clipboard
      hicolor-icon-theme
      adwaita-icon-theme
    ];

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      _JAVA_AWT_WM_NONREPARENTING = "1";
    };
  };
}
