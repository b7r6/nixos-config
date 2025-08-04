{ pkgs, ... }:
{

  home.packages = with pkgs; [
    _1password-cli
    _1password-gui-beta
    brave
    discord
    nemo
    pavucontrol
    slack
    slack-term
    spotify
    spotify-cli-linux
    spotify-tray
    telegram-desktop
    whatsie
    zoom-us
  ];

  fonts.fontconfig.enable = true;
}
