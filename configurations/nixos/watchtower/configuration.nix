{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
  ];

  # ── Incremental rollout ─────────────────────────────────────────────────────
  # Modules self-wire their own agenix secrets, so staging is just enabling
  # service modules one at a time (each is its own `enable`), rebuilding +
  # verifying between. The safe baseline is tailscale + ssh with NO service
  # modules enabled; then attic-node; then backup. To stage, comment a block out.

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelParams = [ "amd_pstate=active" ];
  powerManagement.cpuFreqGovernor = "performance";
  services.thermald.enable = true;

  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
  };

  networking.hostName = "watchtower";
  networking.networkmanager.enable = true;

  # ── Tailscale safety net (ALWAYS on) ────────────────────────────────────────
  # Declarative enrollment so this remote box can't fall off the tailnet during
  # the incremental rollout — if a rebuild restarts tailscaled, it re-auths from
  # the key rather than stranding the node. Tested live on ultraviolence first.
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # watchtower hosts the shared postgres (and atticd). The firewall is now ON
  # fleet-wide by default (so the postgres module's interface-scoped 5432 rule on
  # tailscale0 takes effect everywhere); this explicit = true is redundant but
  # kept as a load-bearing assertion for the DB host.
  hyper-modern-nixos.network.firewall.enable = true;

  # ── Split-horizon DNS (CoreDNS, generated from the topology registry) ───────
  # watchtower is the fleet resolver: authoritative for sju1.s4.gl (host +
  # lan.<host> + service-alias records derived from registry/), forwards the rest
  # (MagicDNS first). LAN clients (the Google TV) point DNS here for lan.* names.
  hyper-modern-nixos.coredns.enable = true;

  # ── PostgreSQL PITR (pgBackRest → R2) ───────────────────────────────────────
  # watchtower is the system-of-record DB host. Continuous WAL archiving + base
  # backups to the dedicated straylight-pg-pitr R2 bucket give ~seconds RPO on
  # this single node — a wipe loses almost nothing. The module self-wires the
  # pgbackrest-r2-env agenix secret; logical dumps stay on as the independent,
  # cross-PG-major fallback. See docs/infrastructure/backups.md#postgresql-backups.
  hyper-modern-nixos.databases.postgres.backup.pitr.enable = true;

  # ── OCI registry (zot → R2) ─────────────────────────────────────────────────
  # Blobs in the straylight-oci R2 bucket (reconstructible — not restic'd).
  # Non-daemon systemd service; self-wires the zot-r2-env agenix creds. Now bound
  # to LOOPBACK and fronted by nginx (below) on registry.sju1.s4.gl with a real
  # cert — the converged pattern from networking.md.
  hyper-modern-nixos.registry = {
    enable = true;
    listenAddress = "127.0.0.1";
  };

  # ── NativeLink: the fleet SCHEDULER (+ CAS shard + worker) ───────────────────
  # Topology from the typed Dhall fleet (out/watchtower.json): scheduler +
  # worker_api (workers fleet-wide dial grpc://watchtower.sju1.s4.gl:50061) + this
  # node's CAS shard (weight 4) + an x86_64 worker. R2 is the shared slow tier.
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;
  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = "watchtower";
    openFirewall = true;
    r2 = {
      enable = true;
      accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
      bucket = "straylight-nativelink-cas";
      environmentFile = "/run/agenix/nativelink-r2-env";
    };
  };

  # ── Supabase (full self-hosted stack) ───────────────────────────────────────
  # Phase one: a SELF-CONTAINED Supabase on its OWN postgres cluster
  # (/var/lib/supabase/db) — it connects to NOTHING in the existing fleet, so
  # atticd's cluster, signing keypair, and pgBackRest `main` stanza are untouched.
  # Kong (the one ingress) binds loopback; nginx fronts it on studio.sju1.s4.gl
  # with the wildcard cert. The module self-wires the supabase-env agenix bundle
  # (generate it with `nix run .#gen-supabase-secrets`). See
  # docs/src/services/supabase.md. Browsing atticd/Forgejo in Studio + CDC to
  # ClickHouse are deferred to post-rewrite.
  hyper-modern-nixos.supabase = {
    enable = true;
    publicUrl = "https://studio.sju1.s4.gl";
  };

  # ── Reverse proxy + internal ACME (nginx → loopback services) ───────────────
  # nginx terminates TLS on the logical names with a real wildcard cert
  # (*.sju1.s4.gl via DNS-01/Njalla) and proxies to loopback. registry.sju1.s4.gl
  # → the zot above; studio.sju1.s4.gl → Kong (Supabase's gateway). CoreDNS
  # already resolves those names to this host.
  hyper-modern-nixos.reverseProxy = {
    enable = true;
    services.registry = {
      port = 5000;
      # OCI image layers are multi-MB/GB; the default 1m cap → HTTP 413 on push.
      maxBodySize = "0";
    };
    services.studio.port = 8000; # → Kong → Studio/auth/rest/realtime/storage
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    # RADV is now the default Vulkan driver
  };

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

  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # tailscale auth-key secret (host-wired opt-in; the module consumes the path).
  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;

  # ── Central cache node: monolithic-shared (the fleet backend) ───────────────
  # watchtower hosts the single shared postgres + the monolithic atticd that runs
  # migrations + serves + the ONLY garbage collector (gc can't be replicated).
  # The profile bundles it all (tailnet postgres with the atticd role+db, atticd
  # over loopback, R2 storage) and SELF-WIRES its secrets (atticd-rs256,
  # attic-push-token, attic-cache-keypair) — so this is the whole declaration.
  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "monolithic-shared";
  };

  # ── restic → Cloudflare R2 backups ──────────────────────────────────────────
  # Per-host repo: s3:…/backups-restic/watchtower (isolated locks + retention).
  # The module self-wires its secrets from the names below. FIRST run is BY HAND
  # (see the runbook / docs) before this timer is trusted:
  #   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  #     env $(sudo cat /run/agenix/restic-r2-env.watchtower | xargs) restic init
  #   …then one manual `restic backup /home` + `restic snapshots` to verify.
  # Starting with /home only; widen to /etc + /var/lib once trusted.
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.watchtower";
    paths = [ "/home" ];
  };

  system.stateVersion = "25.05";
}
