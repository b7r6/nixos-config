{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hypermodern.nixos.usb;
in
{
  options.hypermodern.nixos.usb = {
    enable = mkEnableOption "hypermodern.nixos.usb" // {
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
