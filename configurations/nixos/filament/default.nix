{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self disko;
in
{
  # Deliberately NOT self.nixosModules.default (the fleet stack): filament is
  # a boring standalone JetPack box — just the platform + disk + the minimal
  # base in ./configuration.nix. See that file for the rationale.
  imports = [
    disko.nixosModules.disko
    self.nixosModules.jetson-thor
    ./configuration.nix
    ./disko.nix
  ];

  # Jetson AGX Thor is aarch64
  nixpkgs.hostPlatform = "aarch64-linux";
}
