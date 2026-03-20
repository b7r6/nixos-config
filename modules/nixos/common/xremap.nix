{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [ inputs.xremap-flake.nixosModules.default ];

  # Explicitly disable to suppress the default-value warning
  services.xremap.enable = false;
}
