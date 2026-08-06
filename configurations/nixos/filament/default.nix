{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self disko;
in
{
  imports = [
    disko.nixosModules.disko
    self.nixosModules.default
    self.nixosModules.jetson-thor
    ./configuration.nix
    ./disko.nix
  ];

  # Jetson AGX Thor is aarch64
  nixpkgs.hostPlatform = "aarch64-linux";
}
