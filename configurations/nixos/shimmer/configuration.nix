# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // shimmer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# DGX Spark (GB10 Grace Blackwell) - Primary inference development workstation
#
{
  flake,
  pkgs,
  lib,
  ...
}:
let
  inherit (flake) inputs;
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
    inputs.agenix.nixosModules.default
  ];

  # ── attic api-server replica (shared pg + R2 + RS256, local substituter) ────
  # shimmer is aarch64; the cache stores per-system paths so this just adds the
  # aarch64 closures to the shared cache. Connects to watchtower's postgres over
  # the tailnet like every other replica.
  age.secrets.atticd-rs256.file = ../../../secrets/agenix/machines/atticd-rs256.age;
  age.secrets.attic-push-token.file = ../../../secrets/agenix/machines/attic-push-token.age;
  hyper-modern-nixos.attic-replica.enable = true;

  networking.hostName = "shimmer";

  time.timeZone = "America/Puerto_Rico";

  # Enable DGX Spark hardware support (custom NVIDIA kernel, watchdog, etc.)
  hardware.dgx-spark.enable = true;
  # NOTE: useNvidiaKernel=true (6.17.1 NVIDIA kernel) is broken until nixpkgs/HM
  # fix the nvidia-kernel-modules allowedReferences issue for non-default kernels.
  # The standard kernel works fine — it includes r8127 for the on-board 10GbE.
  hardware.dgx-spark.useNvidiaKernel = false;

  # nvidia-container-toolkit's CDI generator fails on this host (driver/library
  # version mismatch with the standard kernel); keep the package available but
  # don't try to generate specs at boot.
  hardware.nvidia-container-toolkit.enable = false;

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

  # NOTE: the nix-ld ldconfig activation script was disabled during DGX bringup;
  # it raced/failed against the standard-kernel driver setup. NIX_LD_LIBRARY_PATH
  # below is sufficient for the CUDA/Electron unpatched-binary use case.
  # system.activationScripts.nix-ld-cache = ''
  #   if [ -e /run/current-system/sw/bin/ldconfig ]; then
  #     echo "Updating nix-ld cache..."
  #     /run/current-system/sw/bin/ldconfig || true
  #   fi
  # '';

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

  # ── Per-host monitor & display config ──────────────────────────────────────
  # Monitor layout is the single source of truth in lib/monitors.nix; see that
  # file for why it lives there rather than being duplicated between here and
  # the standalone home config.
  home-manager.users.b7r6 = {
    hyper-modern-nixos = {
      hyprland.monitors = (import ../../../lib/monitors.nix).shimmer;

      themes.display = {
        profile = "lg-ultragear-oled";
        highDPI = false; # primary is the 1440p ultrawide at 1.0x
        width = 3440;
        height = 1440;
      };
    };
  };

  system.stateVersion = "25.11";
}
