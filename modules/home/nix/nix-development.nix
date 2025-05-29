{ config, lib, pkgs, ... }: {
  home.packages = with pkgs; [ nixd nixfmt-rfc-style manix statix treefmt ];
}
