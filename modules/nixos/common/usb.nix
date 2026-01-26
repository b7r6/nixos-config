{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hypermodern.usb;
in
{
  options.hypermodern.usb = {
    enable = mkEnableOption "hypermodern.usb" // {
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
