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

  hyper-modern-nixos.themed-shell.enable = true;
}
