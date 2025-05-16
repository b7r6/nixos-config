{ config, lib, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.bluetooth;
in
{
  options.hyper-modern-nixos.bluetooth = {
    enable = mkEnableOption "hyper-modern-nixos.bluetooth" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    services.blueman.enable = true;
  };
}
