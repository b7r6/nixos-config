{ flake, lib, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    inputs.agenix.homeManagerModules.default
    inputs.impurity.nixosModules.default

    self.homeModules.default

    # nh home switch evaluates standalone, so per-machine monitors must be
    # imported here too. See configurations/nixos/<host>/configuration.nix
    # for the equivalent NixOS-level override.
    ./monitors/ultraviolence.nix
  ];

  # impurity.nix - set configRoot, enable via -impure variant
  # impurity.configRoot = self;

  me = {
    username = "b7r6";
    fullname = "b7r6";
    email = "b7r6@b7r6.net";
  };

  # TODO[b7r6]: this probably belongs in a central place
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  home.stateVersion = "25.05";
}
