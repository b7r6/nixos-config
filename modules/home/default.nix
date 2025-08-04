{ pkgs, ... }:
{
  imports = [
    # user identity
    ./me.nix

    # baseline toolchain presets
    ./cloud
    ./dev
    ./llm
    ./nix

    # terminal tooling
    ./emacs
    ./neovim
    ./shell
    ./terminal
    ./themes

    # session management
    ./session

    # optional desktop environments
    ./desktop
    ./wayland
    ./vscode
  ];

  hyper-modern-nixos.themes = {
    enable = true;
    theme = "ono-sendai";
    variant = "chiba";

    display = {
      profile = "samsung-e6";
      highDPI = false;
      width = 3840;
      height = 2400;
    };
  };

  home.packages = with pkgs; [
    dbus
    dconf
  ];
}
