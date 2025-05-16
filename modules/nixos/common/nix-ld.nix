{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.nix-ld;
in
{
  options.hyper-modern-nixos.nix-ld = {
    enable = mkEnableOption "hyper-modern-nixos.nix-ld" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [
      bzip2
      curl
      gdbm
      icu
      libffi
      libunwind
      libuuid
      libuv
      ncurses
      openssl
      readline
      sqlite
      stdenv.cc.cc
      xz
      zlib
    ];
  };
}
