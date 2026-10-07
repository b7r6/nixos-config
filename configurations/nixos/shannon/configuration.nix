{ flake, lib, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "shannon";
  networking.networkmanager.enable = true;

  # ── attic api-server replica (module self-wires its secrets) ────────────────

  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
  };

  # ── OTel agent (host metrics + journald → watchtower gateway) ──────────────

  hyper-modern-nixos.observability.otel.agent = {
    enable = true;

    scrapeTargets = [
      "127.0.0.1:9153" # coredns
      "127.0.0.1:9363" # clickhouse
      "127.0.0.1:9364" # clickhouse-keeper
    ];
  };

  # ── NativeLink: the whole fleet in one laptop (scheduler + CAS + worker) ────
  # Fleet sell-off 2026-10-07: shannon inherits the scheduler role and is the
  # only shard in the CAS ring (weight 1, 16G fast tier — disk-constrained).
  # R2 remains the slow tier, so cache contents outlive this disk.
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;

  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = "shannon";
    openFirewall = true;

    r2 = {
      enable = true;
      accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
      bucket = "straylight-nativelink-cas";
      environmentFile = "/run/agenix/nativelink-r2-env";
    };
  };

  # ── ClickHouse: single-node keeper + server, S3→R2 durable tier ─────────────
  # Keeper membership is registry-derived (shannon is the only host tagged
  # `clickhouse-keeper` after the sell-off → 1-node ensemble). The server's
  # local disk is reconstructible cache; R2 is the durable truth.
  hyper-modern-nixos.databases.clickhouse = {
    keeper = {
      enable = true;
      # One box IS the fleet now; durability is the S3→R2 tier, not quorum.
      allowSolo = true;
    };
    server = {
      enable = true;
      s3.enable = true;
    };
  };

  # ── CoreDNS as this node's own resolver (serves s4.gl — git, auth, grafana) ─
  # Last fleet holdout: without it, flake inputs from git.s4.gl can't resolve
  # off-tailnet-DNS and the attic replica can't look up watchtower.
  hyper-modern-nixos.coredns.enable = true;

  # ── nativelink nix-cache: bounded fast tier over R2 ────────────────────────
  # Re-enabled (fleet default) after the 2026-10-07 disk incident, but with the
  # local fast tier capped: with r2.enable the NAR store is fastSlow(local, R2
  # nix-nar/), so eviction from the 32G local tier never loses data — R2 is the
  # durable copy. The uncapped default grew to 201G on this ~1T laptop.
  hyper-modern-nixos.nativelink.nixCache.fastCacheBytes = 34359738368; # 32 GiB

  # ── Tailscale safety net ────────────────────────────────────────────────────

  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
  hyper-modern-nixos.network.tailscale.exitNodeRotation.enable = true;

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────

  # Per-host repo (backups-restic/shannon). FIRST init:  nix run .#restic-init -- shannon
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.shannon";
    paths = [ "/home" ];
  };

  # ── laptop backpressure: swap-backed memory pressure + early OOM relief ────
  # zram gives systemd-oomd a pressure signal to act on; without swap it goes
  # straight from "fine" to kernel OOM/lockup under big parallel builds.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  systemd.oomd = {
    enableRootSlice = true;
    enableUserSlices = true;
    extraConfig.DefaultMemoryPressureDurationSec = "20s";
  };

  # /bin/bash etc. for FHS-assuming tools (Bazel genrules, scripts).
  services.envfs.enable = true;

  # The registry IFDs (dhall→JSON) build on each host's platform; gossamer and
  # shimmer are native aarch64, so evaluating/`nix flake check`-ing the fleet
  # from this laptop needs aarch64 build capability. The renders are tiny —
  # qemu-user emulation is more than enough.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  environment.variables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  programs.firefox.enable = true;

  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "America/New_York";
  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # ── Wayland/Hyprland ────────────────────────────────────────────────────────
  hyper-modern-nixos.wayland.enable = true;

  # Battery reporting for the new-suzuki shell (BatteryService reads UPower)
  services.upower.enable = true;

  # ── Per-host monitor & display config ──────────────────────────────────────
  home-manager.users.b7r6 = {
    hyper-modern-nixos = {
      hyprland.monitors = (import ../../../lib/monitors.nix).shannon;

      themes.display = {
        # Samsung OLED internal panel at scale 2.0 → 192dpi logical
        profile = "oled";
        highDPI = true;
        width = 2880;
        height = 1800;
      };

      # ── The rice ─────────────────────────────────────────────────────────
      # Same shell as gossamer/shimmer: new-suzuki + wintermute, exclusive
      # mode replaces waybar/wofi/mako and takes the keybinds. No cudaField —
      # the panel is driven by the AMD iGPU, the QML wallpaper does the work.
      new-suzuki = {
        enable = true;
        exclusive = true;
      };
    };
  };

  system.stateVersion = "25.05"; # Did you read the comment?
}
