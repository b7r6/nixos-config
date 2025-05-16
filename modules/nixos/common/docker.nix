{ config, lib, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.docker;
in
{
  options.hyper-modern-nixos.docker = {
    enable = mkEnableOption "hyper-modern-nixos.docker" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune.enable = true;
    };

    virtualisation.podman = {
      enable = false;
      dockerCompat = false;
    };
  };
}
