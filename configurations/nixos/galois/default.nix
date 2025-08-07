{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    self.nixosModules.themes
    self.nixosModules.wayland
    self.nixosModules.hyprland
    ./configuration.nix
  ];
}
