# Sops-nix module for NixOS
# This module installs packages for working with sops-nix
# but doesn't import the sops-nix module directly to avoid
# circular dependencies

{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Just install sops packages by default
  # Actual sops-nix module import happens in top-level configs
  config = {
    environment.systemPackages = [
      pkgs.age
      pkgs.sops
    ];
  };
}
