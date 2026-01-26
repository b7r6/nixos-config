{ config, lib, ... }:
with lib;
let
  cfg = config.hypermodern.bluetooth;
in
{
  options.hypermodern.bluetooth = {
    enable = mkEnableOption "hypermodern.bluetooth" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
    services.blueman.enable = true;
  };
}
