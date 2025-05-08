{pkgs, ...}: {
  home.packages = with pkgs; [
    age-plugin-yubikey
    fido2-manage
    rage
    ragenix
    yubikey-manager
    yubikey-personalization
    yubioath-flutter
    _1password-cli
  ];
}
