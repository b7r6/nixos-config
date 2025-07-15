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

  hypermodern.nixos.themed-shell.enable = true;
}
