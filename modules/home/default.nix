{ inputs, ... }:
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
    # ./vscode
  ];

  hyper-modern-nixos.themes = {
    enable = true;
    theme = "ono-sendai";
    variant = "chiba";

    display = {
      profile = "samsung-e6";
      highDPI = true;
      width = 3840;
      height = 2400;
    };

    overrides = {
      fontSizes = {
        desktop = 14;
        applications = 14;
        terminal = 14;
        popups = 14;
      };
    };
  };
}
