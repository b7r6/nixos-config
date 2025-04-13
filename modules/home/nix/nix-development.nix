{
  config,
  lib,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    nixd
    nixfmt-rfc-style
    nixpkgs-fmt
    manix
    statix
    treefmt
  ];
}
