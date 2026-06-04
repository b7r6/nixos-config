{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    inputs.agenix.homeManagerModules.default
    inputs.impurity.nixosModules.default

    # impermanence home-manager module is auto-imported by nixos module now
    self.homeModules.default
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
  home.enableNixpkgsReleaseCheck = false;
}
