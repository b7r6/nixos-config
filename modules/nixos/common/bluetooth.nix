{ config, lib, ... }:
with lib;
let
  cfg = config.hypermodern.nixos.bluetooth;
in
{
  options.hypermodern.nixos.bluetooth = {
    enable = mkEnableOption "hypermodern.nixos.bluetooth" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    services.blueman.enable = true;
  };
}
