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

      glibc
      gcc-unwrapped.lib
      libGL
      libGLU

      # CUDA libs managed via nvidia-sdk containers
      linuxPackages.nvidia_x11

      # Add these for OpenCV support
      glib
      glib.out
      gtk3
      cairo
      pango
      gdk-pixbuf
      atk
      gobject-introspection

      # Additional libraries often needed by OpenCV
      libpng
      libjpeg
      libtiff
      libwebp
      openjpeg
      ffmpeg

      # X11 libraries that might be needed
      libx11
      libxext
      libxrender
      libxi
      libxfixes
    ];
  };
}
