# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // shimmer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# DGX Spark (GB10 Grace Blackwell) - Primary inference development workstation
#
{
  config,
  pkgs,
  lib,
  ...
}:
let
  libraries = with pkgs; [
    atk
    bzip2
    cairo
    curl
    ffmpeg
    gcc-unwrapped.lib
    gdbm
    gdk-pixbuf
    glib
    glib.out
    glibc
    gobject-introspection
    gtk3
    icu
    libGL
    libGLU
    libffi
    libjpeg
    libpng
    libtiff
    libunwind
    libuuid
    libuv
    libwebp
    ncurses
    openjpeg
    openssl
    pango
    readline
    sqlite
    stdenv.cc.cc.lib
    libx11
    libxext
    libxfixes
    libxi
    libxrender
    xz
    zlib

    # Electron/Chromium dependencies
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cups
    dbus
    expat
    libdrm
    libsecret
    libxkbcommon
    mesa
    nspr
    nss
    pipewire
    libpulseaudio
    libxcomposite
    libxdamage
    libxrandr
    libxcb
    libxcursor
    libxtst
    libxscrnsaver
  ];
in
{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "shimmer";

  # Enable DGX Spark hardware support (custom NVIDIA kernel, watchdog, etc.)
  hardware.dgx-spark.enable = true;

  # Use podman instead of docker for NVIDIA containers on DGX Spark
  hyper-modern-nixos.docker.enable = false;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Wayland/Hyprland
  hyper-modern-nixos.wayland.enable = true;

  # Static IP for ConnectX-7 QSFP direct link to gossamer
  networking.interfaces.enP2p1s0f1np1 = {
    ipv4.addresses = [
      {
        address = "10.0.1.1";
        prefixLength = 24;
      }
    ];
  };

  # nix-ld for running unpatched binaries (CUDA containers, etc.)
  programs.nix-ld = {
    enable = true;
    inherit libraries;
  };

  system.activationScripts.nix-ld-cache = ''
    if [ -e /run/current-system/sw/bin/ldconfig ]; then
      echo "Updating nix-ld cache..."
      /run/current-system/sw/bin/ldconfig || true
    fi
  '';

  environment.sessionVariables = {
    NIX_LD_LIBRARY_PATH = lib.mkForce (lib.makeLibraryPath libraries);
  };

  # Graphics with NVIDIA
  hardware.graphics = {
    enable = true;

    extraPackages = with pkgs; [
      nvidia-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  # Additional kernel modules for GB10
  boot.kernelModules = [
    "nvidia"
    "nvidia_drm"
    "nvidia_modeset"
    "nvidia_uvm"
    "kvm"
  ];

  boot.extraModprobeConfig = ''
    options nvidia-drm modeset=1
  '';

  # Audio (PipeWire)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Shimmer-specific packages
  environment.systemPackages = with pkgs; [
    emacs30-pgtk
    libsecret # For Electron apps
  ];

  system.stateVersion = "25.11";
}
