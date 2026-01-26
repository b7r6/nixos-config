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

  hypermodern.themed-shell.enable = true;
}
