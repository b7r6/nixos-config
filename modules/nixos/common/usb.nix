{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.usb;
in
{
  options.hyper-modern-nixos.usb = {
    enable = mkEnableOption "hyper-modern-nixos.usb" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      libinput
      usbtop
      usbutils
      usbview
    ];
  };
}
