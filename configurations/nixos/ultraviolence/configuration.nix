{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
  ];

  # ── Tailscale declarative enrollment (test bed) ─────────────────────────────
  # ultraviolence is already on the tailnet; wiring authKeyFile just makes
  # enrollment declarative (idempotent — tailscaled won't re-auth a Running
  # node). This proves the auth-key secret + module path before we rely on it to
  # bring up remote hosts.
  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale = {
    authKeyFile = "/run/agenix/tailscale-auth-key";
    # Route all egress through the Mullvad Miami exit node (add-on activated in
    # the Tailscale console). Applied via the tailscale-exit-node oneshot, with
    # --exit-node-allow-lan-access so the LAN/tailnet stays reachable. One of 6
    # us-mia-* nodes; if Mullvad retires -001, switch to another at runtime
    # (`tailscale set --exit-node=<node>`) or update here.
    exitNode = "us-mia-wg-001.mullvad.ts.net";
  };

  # NOTE: the system rclone mount (/mnt/r2/common + /mnt/r2/ultraviolence) and
  # its rclone-conf secret are now fleet defaults — see modules/nixos/default.nix
  # and modules/nixos/rclone-mount.nix. Nothing host-specific to declare here.

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────
  # The module self-wires its secrets from the names below (per-host R2 env:
  # restic-r2-env.ultraviolence). RESTIC_REPOSITORY + creds live in that env
  # file (R2 account id out of the store). FIRST init/backup BY HAND (see docs)
  # before this timer is trusted. /home only first; widen later.
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.ultraviolence";
    paths = [ "/home" ];
  };

  # ── attic binary cache: REPLICA (api-server against watchtower's central pg) ─
  # Stateless api-server replica: connects to watchtower's postgres over the
  # tailnet, shares the R2 chunk store + RS256 secret, consults its OWN
  # localhost:8080 first, watch-store pushes every build (dedup vs R2). The
  # module SELF-WIRES its agenix secrets (atticd-rs256, attic-push-token).
  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
  };

  # ── Incubating services (tailnet-only) ──────────────────────────────────────
  # SearXNG metasearch + transmission/flood torrent stack, both reachable on the
  # tailnet. When ultraviolence routes through the Mullvad Miami exit node
  # (`tailscale set --exit-node=<mullvad-mia>`), all egress — including
  # transmission — exits Miami (no separate killswitch, per the chosen posture).
  age.secrets.searxng-env.file = ../../../secrets/agenix/machines/searxng-env.age;
  age.secrets.transmission-rpc.file = ../../../secrets/agenix/machines/transmission-rpc.age;

  hyper-modern-nixos.searxng = {
    enable = true;
    # Bind broad so it's reachable on the tailnet (binding the tailscale0 IP
    # directly races boot — the iface may not exist yet). The firewall (ON
    # fleet-wide) is the enforcement layer: searxng's port is opened ONLY on
    # tailscale0, so this is NOT exposed publicly despite the 0.0.0.0 bind.
    listenAddress = "0.0.0.0";
    port = 8889; # 8888 is taken by the hatchet docker container on this host
  };

  hyper-modern-nixos.torrents.enable = true;

  # ── NativeLink remote execution (single-box monolithic bringup) ─────────────
  # CAS + scheduler + a local x86_64 worker, all on this host. Split the aarch64
  # worker out to shimmer later by adding role = "worker" there pointing at this
  # host's worker_api over the tailnet. Builds from source (~1000 derivations)
  # unless nativelink.cachix.org is added in modules/nixos/common/nix.nix.
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;

  hyper-modern-nixos.nativelink = {
    enable = true;
    role = "monolithic";
    # Binds all interfaces (TLS-terminated, see tls below) so tailnet clients can
    # reach it; the firewall (ON fleet-wide) opens :50051 ONLY on tailscale0, so
    # it is NOT internet-exposed. worker_api stays loopback (private backend).
    publicListen = "0.0.0.0:50051";
    workerApiListen = "127.0.0.1:50061";
    workerApiEndpoint = "grpc://127.0.0.1:50061";
    openFirewall = true;

    # TLS terminates at the listener with a real Tailscale-issued cert for this
    # node's MagicDNS name, so tailnet clients connect over grpcs:// (tls=true)
    # and trust it without a custom CA. Tailnet HTTPS must be enabled (it is).
    tls = {
      enable = true;
      tailscale = {
        enable = true;
        domain = "ultraviolence.osiris-walleye.ts.net";
      };
    };

    # CAS/AC backed by R2 with a local fast tier. Sizes overridden DOWN from the
    # 256 GiB/32 GiB module defaults until this box's disk is cleaned up.
    r2 = {
      enable = true;
      accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
      bucket = "straylight-nativelink-cas";
      environmentFile = "/run/agenix/nativelink-r2-env";
    };
    localCacheBytes = 68719476736; # 64 GiB local NVMe fast tier (was 256)
    memoryCacheBytes = 8589934592; # 8 GiB memory index (was 32)
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/8d797692-927e-46c4-8047-0c9ea975a41f";
    fsType = "btrfs";
    options = [
      "subvol=@"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
      "ssd"
      "discard=async"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8959-4D56";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  hyper-modern-nixos.hyper-wayland = {
    enable = true;
  };

  hyper-modern-nixos.nvidia = {
    enable = true;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.enableRedistributableFirmware = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Bluetooth management GUI
  services.blueman.enable = true;

  # CPU and system optimizations
  boot.kernelParams = [ "pcie_aspm=off" ];
  powerManagement.cpuFreqGovernor = "performance";
  hardware.cpu.amd.updateMicrocode = true;

  networking.hostName = "ultraviolence";
  networking.networkmanager.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.thermald.enable = true;

  time.timeZone = "America/New_York";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # ── Per-host display config ────────────────────────────────────────────────

  # Monitor layout is the single source of truth in lib/monitors.nix.
  home-manager.users.b7r6 = {
    hyper-modern-nixos = {
      hyprland.monitors = (import ../../../lib/monitors.nix).ultraviolence;

      themes.display = {
        profile = "lg-ultragear-oled";
        highDPI = true;
        width = 3840;
        height = 2160;
      };
    };
  };

  system.stateVersion = "25.05";
}
