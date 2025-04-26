{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    inputs.self.nixosModules.common
  ];
}
