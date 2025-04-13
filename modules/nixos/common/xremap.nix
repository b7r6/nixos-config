{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    inputs.xremap-flake.nixosModules.default
  ];
}
