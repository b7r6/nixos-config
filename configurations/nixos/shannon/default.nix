{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self disko;
in
{
  imports = [
    self.nixosModules.default
    disko.nixosModules.disko
    ./disko.nix
    ./configuration.nix
  ];
}
