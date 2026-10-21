# railgun — a headless Azure dev box (D64s_v5, westeurope). Not a soak host:
# the full home config is ON (this is the point of the machine), the desktop
# layers (Hyprland/Wayland/desktop apps) are OFF because there is no seat.
# Installed with nixos-anywhere --build-on remote; later deploys build here.
{ flake, lib, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self disko agenix;
in
{
  imports = [
    self.nixosModules.default
    agenix.nixosModules.default
    disko.nixosModules.disko
    ../nl-az/disko.nix # gen2 Azure VM, single SCSI OS disk (/dev/sda): 1 GiB ESP + ext4 root
    ./grafana.nix # the wall: fleet + NativeLink dashboards (lane: grafana)
    ./forge.nix # ORBITAL // FORGE: Forgejo + backend + Halogen UI (lane: forge)
    ./nl-bes.nix # Build Event Service ingest + /api/bes (lane: bes)
    ./nl-inspect.nix # REAPI/CAS inspector + /api/re (lane: inspect)
    ./nl-traffic.nix # continuous Bazel traffic against the scheduler (lane: traffic)
    ./nativelink-ui.nix # ORBITAL // NATIVELINK: the console at nativelink.s4.gl
    ./previews.nix # nlp-<screen>/fgp-<screen>.s4.gl: per-screen preview hosts (design program)
    ./auth.nix # Kanidm at auth.s4.gl: OIDC for Forgejo + Grafana
  ];

  networking.hostName = "railgun";

  # Azure platform (Hyper-V guest, serial console, headless). It forces the
  # home config off for the soak fleet; railgun wants it back.
  hyper-modern-nixos.azure.enable = true;
  hyper-modern-nixos.identity.homeManager = lib.mkForce true;

  # Fleet tailnet, declaratively, from the repo's global auth key.
  # The tailnet is about to be rotated (2026-10): until railgun is on the new
  # one, the way in is the STATIC public IP (20.91.238.153) on tcp/22, which the
  # NSG (rg railgun-swedencentral) and the fleet firewall (22 on every
  # interface) both admit. Do not scope sshd to tailscale0 before the rotation
  # lands; `az serial-console connect` (ttyS0) is the last resort.
  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # ── R2 nix cache: what railgun builds goes to the fleet's durable cache ──
  # The Azure module mkForces the nativelink nix_cache + store watcher off
  # (soak nodes never build); railgun is the opposite: a 64-core builder whose
  # output the laptop wants. Same shape as shannon: local fast tier capped,
  # R2 as the slow tier, read-through of the public caches. mkOverride 40 beats
  # the module's mkForce (50).
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;
  hyper-modern-nixos.nativelink.r2 = {
    enable = true;
    accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
    bucket = "straylight-nativelink-cas";
    environmentFile = "/run/agenix/nativelink-r2-env";
  };
  hyper-modern-nixos.nativelink.nixCache = {
    enable = lib.mkOverride 40 true;
    watchStore = lib.mkOverride 40 true;
    fastCacheBytes = 274877906944; # 256 GiB of the 1 TiB disk
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
  };

  # ── The homelab services stack, on the big box ──────────────────────────────
  # What shannon inherited from the sold fleet (configurations/nixos/shannon),
  # minus the laptop: NativeLink RE (its own one-host site in the Dhall fleet),
  # ClickHouse (+ solo Keeper) with R2 as the durable tier, OTel agent → the
  # gateway on this host, Grafana with the fleet's Dhall dashboards, Postgres,
  # and nginx fronting the UIs under sk1.s4.gl with DNS-01 certs. CoreDNS and
  # the registry entry wait for the real tailnet address (the zone must not
  # publish a placeholder).

  # NativeLink RE: scheduler + CAS shard + worker, per fleet.dhall (sk1 site).
  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = "railgun";
    openFirewall = true; # tailscale0 only, per the module
  };
  # The rendered config dials itself by its fleet fqdn; nothing serves the sk1
  # zone yet, so pin it to loopback (shannon does the same).
  networking.hosts."127.0.0.1" = [ "railgun.sk1.s4.gl" ];

  # ClickHouse: one node, Keeper on loopback (NOT registry-derived — tagging
  # railgun `clickhouse-keeper` would silently add it to shannon's ensemble).
  hyper-modern-nixos.databases.clickhouse = {
    keeper = {
      enable = true;
      allowSolo = true;
      members = [
        {
          physical = "railgun";
          address = "127.0.0.1";
        }
      ];
    };
    server = {
      enable = true;
      s3.enable = true; # R2 durable tier, local cache in front
    };
  };

  # OTel: this host is its own gateway (exporter = ClickHouse). The agent's
  # default endpoint is the registry's `ch` host (shannon) — pin it here.
  hyper-modern-nixos.observability.otel.gateway.enable = true;
  hyper-modern-nixos.observability.otel.agent = {
    enable = true;
    gatewayEndpoint = "127.0.0.1:4317";
    scrapeTargets = [
      "127.0.0.1:9363" # clickhouse
      "127.0.0.1:9364" # clickhouse-keeper
      "127.0.0.1:9153" # coredns
      "127.0.0.1:3300" # grafana (metrics.enabled, unauthenticated /metrics)
    ];
  };

  # Postgres: the shared fleet database, fresh (watchtower's data was wiped).
  # Its daily logical dump (/var/backup/postgres, the forgejo DB included) is
  # an authoritative state path, so the restic run below picks it up.
  hyper-modern-nixos.databases.postgres.enable = true;

  # ── restic → R2 (backups-restic/railgun) ───────────────────────────────────
  # The Forge is the ONLY home of straylight/orbital-nativelink and
  # straylight/orbital-www (pushed here, mirrored nowhere), so Forgejo's repos
  # and data plus the working checkouts under ~/src must leave this disk.
  # NOT the default /var/lib: that would sweep in the NativeLink CAS fast tier
  # and ClickHouse, both reconstructible and far larger than what matters.
  # First run: `systemctl start restic-backups-init` creates the repo once.
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.railgun";
    paths = [
      "/var/lib/forgejo"
      "/home"
      "/etc"
    ];
    # Merged with the module's default excludes (same priority as the default):
    # the PureScript/esbuild build output in the orbital worktrees is ~3 GiB
    # and every byte of it regenerates from the sources it sits beside.
    exclude = lib.mkOptionDefault [
      "**/.spago"
      "**/.build"
      "/home/*/src/hypermodern/*/output"
      "/home/*/src/hypermodern/*/dist"
      "/home/*/src/hypermodern/*/projects/*/output"
      "/home/*/src/hypermodern/*/projects/*/dist"
    ];
  };

  # Grafana lives in ./grafana.nix; Orbital Forge (Forgejo + backend + UI) in ./forge.nix.

  # CoreDNS for the sk1 zone (railgun.sk1.s4.gl, <service>.sk1.s4.gl → railgun),
  # generated from the registry like shannon's sju1 zone.
  hyper-modern-nixos.coredns = {
    enable = true;
    dc = "sk1";
  };

  # nginx in front of the UIs: flat <name>.s4.gl ("we global now"), one
  # wildcard *.s4.gl cert by DNS-01. CoreDNS answers grafana.s4.gl as a CNAME
  # to grafana.sk1.s4.gl → railgun, so the flat name is the one people use.
  hyper-modern-nixos.reverseProxy = {
    enable = true;
    dc = "sk1";
    zone = "s4.gl";
    services.grafana.port = 3300;
    services.ch.port = 8123; # clickhouse HTTP / play UI
    services.git = {
      port = 3200; # Forgejo (./forge.nix)
      maxBodySize = "512m"; # https pushes
    };
    services.forge.root = "/var/www/forge"; # ORBITAL // FORGE UI (./forge.nix)
    services.nativelink.root = "/var/www/nativelink"; # ORBITAL // NATIVELINK console (./nativelink-ui.nix)
  };

  # Bazel RBE against the local scheduler, like shannon's.
  home-manager.users.b7r6.home.file.".bazelrc".text = ''
    build:rbe-local --remote_executor=grpc://127.0.0.1:50051
    build:rbe-local --remote_instance_name=main
    build:rbe-local --remote_timeout=3600
    build:rbe-local --jobs=48
  '';

  # 64 cores, 256 GiB: build everything here, keep the store from eating the disk.
  nix.settings = {
    max-jobs = "auto";
    cores = 0;
    min-free = lib.mkDefault (20 * 1024 * 1024 * 1024);
    max-free = lib.mkDefault (100 * 1024 * 1024 * 1024);
  };
  services.openssh.settings.MaxStartups = "50:30:100";

  # No seat: drop the Wayland/desktop layers of the home config, keep every
  # terminal/editor/toolchain module.
  home-manager.users.b7r6 = {
    # No user-level agenix on this box: the home config's two user secrets
    # (netrc, rclone-conf) decrypt with ~/.ssh/id_ed25519, which deliberately
    # does not exist on railgun (no private keys leave the laptop), so the
    # user@1000 agenix unit failed on every activation (139 errors/h on the
    # wall). Nothing on railgun consumes them.
    age.secrets = lib.mkForce { };
    hyper-modern-nixos = {
      hyprland.enable = lib.mkForce false;
      desktop.enable = lib.mkForce false;
      session.enable = lib.mkForce false;
      vscode.enable = lib.mkForce false;
    };
  };

  system.stateVersion = "25.11";
}
