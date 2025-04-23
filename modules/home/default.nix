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
    # ./terminal
    ./themes

    # session management
    ./session
  ];
}
