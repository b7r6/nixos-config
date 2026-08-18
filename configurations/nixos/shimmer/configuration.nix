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

  # ── attic api-server replica (module self-wires its secrets) ────────────────
  # shimmer is aarch64; the cache stores per-system paths so this adds the
  # aarch64 closures to the shared cache over the tailnet like every replica.
  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
  };

  # ── ClickHouse Keeper (coordination plane) ──────────────────────────────────
  hyper-modern-nixos.databases.clickhouse.keeper.enable = true;

  # ── OTel agent (host metrics + journald → watchtower gateway) ──────────────
  hyper-modern-nixos.observability.otel.agent = {
    enable = true;
    scrapeTargets = [
      "127.0.0.1:9153" # coredns
      "127.0.0.1:9364" # clickhouse-keeper
    ];
  };

  # ── Tailscale safety net ────────────────────────────────────────────────────
  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
  # let the desktop user drive tailscale from the tray (trayscale) without sudo
  hyper-modern-nixos.network.tailscale.operator = "b7r6";

  # CoreDNS as this node's own resolver (resolves *.sju1.s4.gl, incl. the
  # nativelink scheduler/CAS FQDNs; tailscale stops managing resolv.conf).
  hyper-modern-nixos.coredns.enable = true;

  # ── NativeLink: DEFERRED on shimmer (aarch64) ───────────────────────────────
  # shimmer is meant to be the aarch64 CAS shard + executor (fleet.dhall has it,
  # `enabled = False` for now). Blocked: the nativelink flake's LLVM 22 compiler-rt
  # fails to build for aarch64-unknown-linux-musl (sys/auxv.h — musl/bleeding-LLVM
  # break). Re-enable here + flip `enabled = True` in nativelink/fleet.dhall once
  # an aarch64 nativelink artifact builds (cached release, or the musl fix).
  # CoreDNS (above) builds fine on aarch64 and stays on.

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────
  # Per-host repo (backups-restic/shimmer). Module self-wires its secrets.
  # FIRST init declarative + idempotent:  nix run .#restic-init -- shimmer
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.shimmer";
    paths = [ "/home" ];
  };

  networking.hostName = "shimmer";

  # ── keep the screens lit ────────────────────────────────────────────────────
  # The trtllm-dsv4 benchmark harness on gossamer stops display-manager over
  # ssh to free the GB10 during paired runs. The panels stay lit regardless:
  # this timer restarts the display manager within ~30s of anything stopping
  # it. NOTE this puts the compositor + CUDA wallpaper back on the GPU during
  # benchmark runs; for a clean run, pause it first:
  #   sudo systemctl stop keep-dm-lit.timer   (re-enable with start)
  systemd.services.keep-dm-lit = {
    description = "keep-dm-lit — restart display-manager if stopped";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl start display-manager.service";
    };
  };
  systemd.timers.keep-dm-lit = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };

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

    # Floor the graph quantum. The PreSonus AudioBox USB 96 DAC on this box's
    # NVIDIA USB controller (NVDA8000) glitches when PipeWire drives the quantum
    # down to tiny values (observed period_size=128): it produces continuous
    # micro-glitches whose loudness tracks the signal level, i.e. audible
    # "sizzle"/distortion that scales with volume. `aplay -D hw:0` was always
    # clean (large fixed buffer, no dynamic quantum), which localised it to
    # PipeWire scheduling rather than hardware/ALSA. Forcing a larger quantum
    # live made it clean, so we pin a minimum floor here. Bump to 2048 if any
    # crackle returns under heavy load.
    extraConfig.pipewire."50-min-quantum" = {
      "context.properties" = {
        "default.clock.min-quantum" = 1024;
      };
    };
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
  # GB10: the kernel-rendered EYES still behind the login greeter (system)
  # and the lock screen (home) — matches the live wallpaper. Pulls the CUDA
  # SDK, so it's opt-in and only enabled on the Sparks.
  hyper-modern-nixos.greeter.eyesStill = true;

  home-manager.users.b7r6 = {
    hyper-modern-nixos = {
      hyprland.monitors = (import ../../../lib/monitors.nix).shimmer;
      lockscreen.eyesStill = true;

      # ── The rice ─────────────────────────────────────────────────────────
      # Same shell as gossamer: new-suzuki + wintermute, exclusive. Fleet
      # symmetry — one shell story across the Sparks.
      new-suzuki = {
        enable = true;
        exclusive = true;
        # Render with the CUDA kernel and let it own the compositor
        # wallpaper layer. The EYES card: plasma blades + kernel words,
        # both panels, palette morphs riding the color spinor.
        cudaField = {
          enable = true;
          scene = "eyes";
        };
      };

      themes.display = {
        # pair of ASUS PG32UCDP 4K WOLEDs (see lib/monitors.nix b7r6-desk);
        # wallpaper renders at panel resolution, scale 1.0 → 96dpi logical
        profile = "oled";
        highDPI = false;
        width = 3840;
        height = 2160;
      };
    };
  };

  system.stateVersion = "25.11";
}
