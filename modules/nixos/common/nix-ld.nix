{ config, pkgs, ... }:
{
  # System-wide nix-ld configuration
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # Common libraries for all runtimes
    curl
    icu
    libunwind
    libuuid
    openssl
    stdenv.cc.cc
    zlib

    # Python-specific
    bzip2
    gdbm
    libffi
    ncurses
    readline
    sqlite
    xz

    # Node.js-specific
    libuv
  ];

  # Baseline system packages
  environment.systemPackages = with pkgs; [
  ];
}
