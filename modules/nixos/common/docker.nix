{ config, lib, ... }:
with lib;
let
  cfg = config.hypermodern.nixos.docker;
in
{
  options.hypermodern.nixos.docker = {
    enable = mkEnableOption "hypermodern.nixos.docker" // {
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
