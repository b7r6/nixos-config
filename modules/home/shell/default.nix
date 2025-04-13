{
  imports = [
    ./atuin.nix
    ./bash.nix
    ./cli.nix
    ./packages.nix
    ./shell.nix
    ./themed-shell.nix
    ./tmux.nix
  ];

  programs.themed-shell.enable = true;
}
