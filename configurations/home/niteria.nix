{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    inputs.agenix.homeManagerModules.default
    self.homeModules.default
  ];

  me = {
    username = "niteria";
    fullname = "niteria";
    email = "bartosz@fleek.xyz";
  };

  # TODO[b7r6]: this probably belongs in a central place
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  home.stateVersion = "25.05";
}
