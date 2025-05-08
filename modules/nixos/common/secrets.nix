{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    pam_u2f
    yubikey-agent
    yubico-pam
  ];

  programs._1password.enable = true;

  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = ["b7r6"];
  };
}
