# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // gossamer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# DGX Spark (GB10 Grace Blackwell) - Secondary compute/inference node
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

  # ── attic cache replica ─────────────────────────────────────────────────────
  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
  };

  # ── OTel agent (host metrics → watchtower gateway) ─────────────────────────
  hyper-modern-nixos.observability.otel.agent = {
    enable = true;
    scrapeTargets = [ ];
  };

  # ── Tailscale ───────────────────────────────────────────────────────────────
  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────
  # TODO: enable after creating restic-r2-env.gossamer.age and rekeying
  # hyper-modern-nixos.backup = {
  #   enable = true;
  #   passwordSecret = "restic-password";
  #   environmentSecret = "restic-r2-env.gossamer";
  #   paths = [ "/home" ];
  # };

  # ── fwupd (firmware updates — guinea pig) ───────────────────────────────────
  services.fwupd.enable = true;

  networking.hostName = "gossamer";

  time.timeZone = "America/Puerto_Rico";

  # Enable DGX Spark hardware support
  hardware.dgx-spark.enable = true;
  hardware.dgx-spark.useNvidiaKernel = false;

  # nvidia-container-toolkit — try enabling it on this node
  hardware.nvidia-container-toolkit.enable = lib.mkForce false;

  # Use podman for NVIDIA containers
  hyper-modern-nixos.docker.enable = false;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Wayland/Hyprland (display attached for bringup)
  hyper-modern-nixos.wayland.enable = true;

  # Static IP for ConnectX-7 QSFP direct link to shimmer
  networking.interfaces.enP2p1s0f1np1 = {
    ipv4.addresses = [
      {
        address = "10.0.1.2";
        prefixLength = 24;
      }
    ];
  };

  # nix-ld for running unpatched binaries (CUDA containers, etc.)
  programs.nix-ld = {
    enable = true;
    inherit libraries;
  };

  environment.sessionVariables = {
    NIX_LD_LIBRARY_PATH = lib.mkForce (lib.makeLibraryPath libraries);
  };

  # Graphics with NVIDIA
  hardware.graphics = {
    enable = true;

    extraPackages = with pkgs; [
      nvidia-vaapi-driver
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

  # Audio (PipeWire)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Gossamer-specific packages
  environment.systemPackages = with pkgs; [
    emacs30-pgtk
    libsecret
  ];

  # Temporary password for bringup (remove after agenix is rekeyed)
  users.users.b7r6.hashedPassword = "$6$QpgIw8Y2lGHW.p0V$FHHvyLigTUUQv1im2QXztj4G1qN/LARGzCs0DYUmjIT0inLB3BVZfG4j8tVqISFf1.bUvGdocTNeKZR1BAzrT.";

  # ── Per-host monitor & display config ──────────────────────────────────────
  home-manager.users.b7r6 = {
    hyper-modern-nixos = {
      hyprland.monitors = (import ../../../lib/monitors.nix).gossamer;

      themes.display = {
        profile = "lg-ultragear-oled";
        highDPI = true;
        width = 3840;
        height = 2160;
      };
    };
  };

  system.stateVersion = "25.11";
}
