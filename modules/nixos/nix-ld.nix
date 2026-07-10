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
    ]
    # CUDA user-mode driver (libcuda.so). Must track the *running* kernel
    # module, not nixpkgs' default linuxPackages.nvidia_x11 (which lags at
    # 595.84 and injects a stale libcuda.so → CUDA error 803 UMD/KMD mismatch
    # for nix-ld'd binaries such as pip/uv torch wheels). Using the exact
    # driver derivation the KMD is built from keeps libcuda in lockstep.
    # Guarded so non-NVIDIA hosts don't drag in the proprietary driver.
    ++ lib.optional config.hyper-modern-nixos.nvidia.enable config.hardware.nvidia.package;
  };
}
