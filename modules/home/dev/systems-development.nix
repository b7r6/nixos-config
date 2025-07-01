{ pkgs, ... }:
{
  home.packages = with pkgs; [
    clang-tools_19
    gcc
    gnumake
    zig
    zls
  ];
}
