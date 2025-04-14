{
  flake,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.wayland.plasma;
  inherit (flake) inputs;
in
{
  imports = [
  ];
}
