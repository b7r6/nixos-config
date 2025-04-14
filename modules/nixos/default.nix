{ flake, ... }:
{
  imports = [
    flake.inputs.self.nixosModules.common
  ];
}
