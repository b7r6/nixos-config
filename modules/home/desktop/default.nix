{ pkgs, ... }:
{

  home.packages = with pkgs; [
    _1password-cli
    _1password-gui-beta
    brave
    nemo
    pavucontrol
    slack
    slack-term
    spotify
    spotify-cli-linux
    spotify-tray
    telegram-desktop
    zoom-us
    whatsie
  ];

  fonts.fontconfig.enable = true;
}
