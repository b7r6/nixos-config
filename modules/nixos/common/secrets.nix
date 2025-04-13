{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    pam_u2f
    yubikey-agent
    yubico-pam
  ];
}
