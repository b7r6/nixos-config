# impurity.nix integration for live config editing
#
# This module enables impure symlinking for rapid iteration on config files.
# Use case: editing emacs config, hyprland config, etc. without nixos-rebuild.
#
# Usage:
#   1. Build with impurity enabled:
#      IMPURITY_PATH=$(pwd) sudo --preserve-env=IMPURITY_PATH nixos-rebuild switch --flake .#ultraviolence-impure --impure
#
#   2. Edit files in your config repo - changes apply immediately
#
#   3. When done, switch back to pure build to lock changes:
#      nixos-rebuild switch --flake .#ultraviolence
#
{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [ inputs.impurity.nixosModules.impurity ];

  # Set the config root for impurity to resolve paths
  impurity.configRoot = flake.self;

  # impurity.enable is false by default
  # The -impure variant sets it to true
}
