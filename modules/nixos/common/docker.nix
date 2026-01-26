{ config, lib, ... }:
with lib;
let
  cfg = config.hypermodern.docker;
in
{
  options.hypermodern.docker = {
    enable = mkEnableOption "hypermodern.docker" // {
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
