{ pkgs, ... }:
{
  home.packages = with pkgs; [
    pavucontrol
    slack
    slack-term
    spotify
    spotify-cli-linux
    spotify-tray
    telegram-desktop
    zoom-us
  ];
}
