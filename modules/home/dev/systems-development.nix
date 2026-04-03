{ pkgs, ... }:
{
  home.packages = with pkgs; [
    llvmPackages_19.clang-tools
    gcc
    gnumake
    zig
    zls
  ];
}
