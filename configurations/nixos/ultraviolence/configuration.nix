{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
    inputs.vllm-stack.nixosModules.vllm
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
    # exitNode = "us-mia-wg-001.mullvad.ts.net";
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

  # ── Incubating services (tailnet-only) ──────────────────────────────────────

  # SearXNG metasearch + transmission/flood torrent stack, both reachable on the
  # tailnet. flood is ONLY through nginx, gated by Kanidm (oauth2-proxy); SearXNG
  # is ALSO open directly on tailscale0 (unauthed) so its json/csv/rss API is
  # usable as a scripted / LLM web-search backend. When ultraviolence routes
  # through the Mullvad Miami exit node
  # (`tailscale set --exit-node=<mullvad-mia>`), all egress — including
  # transmission — exits Miami (no separate killswitch, per the chosen posture).
  age.secrets.searxng-env.file = ../../../secrets/agenix/machines/searxng-env.age;

  hyper-modern-nixos.searxng = {
    enable = true;
    # Bind 0.0.0.0 (binding the tailscale0 IP directly races boot) and open the
    # port on tailscale0 ONLY — the fleet-wide firewall keeps it off the public
    # internet. Unauthed on the tailnet by design: the limiter/Kanidm gate just
    # block our own JSON API calls. The Kanidm-gated nginx path
    # (searxng.sju1.s4.gl, below) still works for browser use.
    listenAddress = "0.0.0.0";
    port = 8889;
    openTailnet = true;
  };

  # ssoGated: flood's own login is disabled and it connects straight to
  # transmission over loopback, so the Kanidm gate below is the single auth
  # point (no double login, no transmission-rpc secret needed).
  hyper-modern-nixos.torrents = {
    enable = true;
    ssoGated = true;
  };

  # ── Reverse proxy + internal ACME (nginx → loopback services) ───────────────

  # Same pattern as watchtower: wildcard cert (*.sju1.s4.gl via DNS-01/Njalla),
  # nginx terminates TLS on the logical names. CoreDNS resolves them here.
  hyper-modern-nixos.reverseProxy = {
    enable = true;
    services.searxng = {
      port = 8889;
      protected = true;
    };
    services.torrents = {
      port = 3001;
      protected = true;
    };
  };

  # ── oauth2-proxy (gates searxng + flood through Kanidm) ─────────────────────
  age.secrets.oauth2-proxy-secret.file = ../../../secrets/agenix/machines/oauth2-proxy-ultraviolence-secret.age;
  age.secrets.oauth2-proxy-cookie.file = ../../../secrets/agenix/machines/oauth2-proxy-ultraviolence-cookie.age;

  hyper-modern-nixos.oauth2-proxy = {
    enable = true;
    clientId = "ultraviolence-proxy";
    clientSecretFile = "/run/agenix/oauth2-proxy-secret";
    cookieSecretFile = "/run/agenix/oauth2-proxy-cookie";
  };

  # ── NativeLink remote execution (single-box monolithic bringup) ─────────────
  # CAS + scheduler + a local x86_64 worker, all on this host. Split the aarch64
  # worker out to shimmer later by adding role = "worker" there pointing at this
  # host's worker_api over the tailnet. Builds from source (~1000 derivations)
  # unless nativelink.cachix.org is added in modules/nixos/common/nix.nix.
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;

  # CoreDNS as this node's own resolver (resolves *.sju1.s4.gl, incl. the
  # nativelink scheduler/CAS FQDNs; tailscale stops managing resolv.conf).
  hyper-modern-nixos.coredns.enable = true;

  # NativeLink: this host's role + topology come from the typed Dhall fleet
  # (nativelink/fleet.dhall → out/ultraviolence.json): a CAS shard (small, weight
  # 1 — disk pressure) + an x86_64 worker dialing watchtower's scheduler over the
  # tailnet. The Dhall owns ports/stores/workers; the module just runs the config
  # and wires the R2 creds. Plaintext over the encrypted tailnet (no per-listener
  # TLS in the fleet config). See docs/infrastructure/nativelink-production.md.
  hyper-modern-nixos.nativelink = {
    enable = true;

    dhallHost = "ultraviolence";
    openFirewall = true;

    r2 = {
      enable = true;
      accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
      bucket = "straylight-nativelink-cas";
      environmentFile = "/run/agenix/nativelink-r2-env";
    };
  };

  # nix-ld for running unpatched binaries (CUDA containers, etc.)
  programs.nix-ld = {
    enable = true;
  };

  # vLLM OpenAI-compatible server for Qwen3.6-27B-NVFP4-MTP on Blackwell.
  # Uses the NGC python environment from the vllm-stack flake (torch cu130,
  # triton, tensorrt_llm) and caps the GPU at 475W to avoid Xid 79.
  services.vllm = {
    enable = true;
    # openFirewall = true;  # uncomment to expose 8000 beyond localhost
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

  time.timeZone = "America/Puerto_Rico";

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
