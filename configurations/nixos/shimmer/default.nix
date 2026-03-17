{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self disko;
in
{
  imports = [
    disko.nixosModules.disko
    self.nixosModules.default
    ./configuration.nix
    ./disko.nix
  ];

  # DGX Spark is aarch64
  nixpkgs.hostPlatform = "aarch64-linux";
}
