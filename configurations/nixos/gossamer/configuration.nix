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

  # ── NativeLink nix_cache substituter (standalone, R2-backed, aarch64) ───────
  # gossamer is aarch64; the server builds thanks to the compiler-rt-musl overlay
  # in the fork. Standalone (not a fleet CAS/worker node): r2.enable backs the
  # NAR store so local disk is a bounded fast tier and the durable mirror lives
  # in the shared bucket, and the fetchProxy tees raw fetchurl bytes into the CAS.
  # enable/watchStore/signing key are fleet defaults. Pushing gossamer's aarch64
  # closures is exactly the aarch64-shard role shimmer's comment defers.
  # (First deploy required a two-step bootstrap: coredns had to come up before
  # git.s4.gl — the nativelink-nix input host — would resolve.)
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;

  hyper-modern-nixos.nativelink = {
    r2 = {
      enable = true;
      accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
      bucket = "straylight-nativelink-cas";
      environmentFile = "/run/agenix/nativelink-r2-env";
    };

    nixCache = {
      upstreamCaches = [
        {
          url = "https://cache.nixos.org";
          trustedPublicKeys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
        }
        {
          url = "https://nix-community.cachix.org";
          trustedPublicKeys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
        }
      ];
      fetchProxy.enable = true;
    };
  };

  # ── Graceful degradation when secrets aren't available (fresh install) ──────
  # Services that depend on agenix secrets should not block boot if secrets
  # can't be decrypted (e.g. first boot before host key is rekeyed).
  systemd.services.atticd.unitConfig.ConditionPathExists = "/run/agenix/atticd-rs256";
  systemd.services.atticd-watch-store.unitConfig.ConditionPathExists = "/run/agenix/attic-push-token";

  # ── OTel agent (host metrics → watchtower gateway) ─────────────────────────
  hyper-modern-nixos.observability.otel.agent = {
    enable = true;
    scrapeTargets = [
      "127.0.0.1:9153" # coredns
    ];
  };

  # ── Tailscale ───────────────────────────────────────────────────────────────
  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # CoreDNS as this node's own resolver
  hyper-modern-nixos.coredns.enable = true;

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

  # ── Impermanence (btrfs rollback) ──────────────────────────────────────────
  hyper-modern-nixos.impermanence = {
    enable = true;
    device = "/dev/disk/by-partlabel/disk-main-root";
    rollbackRoot = true;
    rollbackUseSystemdInitrd = true;
    users.b7r6 = { };
  };

  # Disko doesn't set neededForBoot on subvolumes; impermanence requires it
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;

  # btrfs tools in initrd for rollback
  boot.initrd.systemd.extraBin = {
    btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
  };

  networking.hostName = "gossamer";

  # ── WiFi reliability (MediaTek MT7925 / Filogic 360, mt7925e) ───────────────
  # Two durable fixes for the onboard Wi-Fi 7 card:
  #   1. Kill NM power-save — the MT7925 drops packets / stalls when the radio
  #      idle-sleeps; disabling it trades a little power for a stable link.
  #   2. disable_aspm=1 — PCIe ASPM is the documented trigger for random
  #      mt7925e firmware death (total radio loss until reload). Preventive.
  networking.networkmanager.wifi.powersave = false;
  boot.extraModprobeConfig = ''
    options mt7925e disable_aspm=1
  '';

  # NM wait-online is useless when primary links are statically configured
  systemd.services.NetworkManager-wait-online.enable = false;

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

    extraPackages = with pkgs; [ nvidia-vaapi-driver ];
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
