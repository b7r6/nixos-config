{ config, lib, ... }:
with lib;
let
  cfg = config.hypermodern.secrets;
in
{
  options.hypermodern.secrets = {
    enable = mkEnableOption "hypermodern.secrets" // {
      default = false;
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      pam_u2f
      yubikey-agent
      yubico-pam
    ];

    programs._1password.enable = true;
    programs._1password-gui = {
      enable = true;
      # TODO[b7r6]: get rid of the hardcode
      polkitPolicyOwners = [ "b7r6" ];
    };
  };
}
