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

  # The fleet package list ships nvtopPackages.nvidia, whose nixpkgs build
  # links cudart — an unsupported stub on the jetson pin. nvtop can't see the
  # Tegra iGPU either way; substitute the intel build to keep the shared
  # package list intact.
  nixpkgs.overlays = [
    (_: prev: {
      nvtopPackages = prev.nvtopPackages // {
        nvidia = prev.nvtopPackages.intel;
      };
    })
  ];
}
