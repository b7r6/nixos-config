{ flake, pkgs, ... }:
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
  # the key rather than stranding the node. Tested live on `ultraviolence`
  # first.

  # TODO[b7r6]: we should use the proper `agenix` path discovery...
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

  # `watchtower` is the system-of-record DB host. Continuous WAL archiving +
  # base backups to the dedicated straylight-pg-pitr R2 bucket give ~seconds
  # RPO on this single node — a wipe loses almost nothing. The module self-wires
  # the pgbackrest-r2-env agenix secret; logical dumps stay on as the
  # independent, cross-PG-major fallback.
  # See docs/infrastructure/backups.md#postgresql-backups.
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

  # ── Supabase (native, daemon-free) ───────────────────────────────────────────

  # No Docker. PG17 from the supabase/postgres flake runs as a native systemd
  # unit on port 5433 (attic's PG16 keeps 5432). GoTrue, PostgREST, imgproxy from
  # nixpkgs. Kong replaced by nginx location blocks. The remaining services
  # (meta, realtime, storage, studio) run as containers pointed at the native DB
  # until their Nix derivations are built. Self-wires the supabase-env agenix
  # bundle (same secret as before). See docs/src/services/supabase.md.
  hyper-modern-nixos.supabase-native = {
    enable = true;
    publicUrl = "https://studio.sju1.s4.gl";

    db.tailnet.enable = true;
    db.pitr.enable = true;

    db.databases = {
      atticd = {
        passwordSecret = "atticd-rs256";
        passwordVar = "PGPASSWORD";
        migrate = {
          enable = true;
          # dump from the old PG16 on default port/socket
          sourcePort = 5432;
          sourceSocketDir = "/run/postgresql";
        };
      };

      forgejo = {
        passwordSecret = "forgejo-db";
        rawPassword = true;
      };
    };
  };

  # ── Forgejo (git forge, native) ───────────────────────────────────────────────

  # Self-hosted git forge on the unified PG17 cluster. Repos on local disk,
  # database in supabase-native. Fronted by nginx on git.sju1.s4.gl.
  age.secrets.forgejo-db.file = ../../../secrets/agenix/machines/forgejo-db.age;

  services.forgejo = {
    enable = true;
    user = "git";
    group = "git";
    stateDir = "/var/lib/forgejo";

    database = {
      type = "postgres";
      host = "127.0.0.1";
      port = 5433;
      name = "forgejo";
      user = "forgejo";
      passwordFile = "/run/agenix/forgejo-db";
      createDatabase = false; # supabase-db-ensure-dbs handles this
    };

    settings = {
      DEFAULT.APP_NAME = "straylight";
      server = {
        DOMAIN = "git.s4.gl";
        ROOT_URL = "https://git.s4.gl/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3200;
        SSH_DOMAIN = "git.s4.gl";
      };
      service = {
        DISABLE_REGISTRATION = true;
      };
      session.PROVIDER = "db";
      cache.ADAPTER = "memory";
      log.LEVEL = "Info";
      metrics.ENABLED = true;
      metrics.ENABLED_ISSUE_BY_REPOSITORY = true;
    };
  };

  # the `git` user/group for forgejo (module only auto-creates `forgejo`)
  users.users.git = {
    isSystemUser = true;
    group = "git";
    home = "/var/lib/forgejo";
    shell = "/bin/sh";
  };

  users.groups.git = { };

  # forgejo must wait for supabase-db-ensure-dbs to create its database + role
  systemd.services.forgejo.after = [ "supabase-db-ensure-dbs.service" ];
  systemd.services.forgejo.requires = [ "supabase-db-ensure-dbs.service" ];

  # ── PG17 daily logical dump (restic picks it up) ──────────────────────────────

  # Full PITR (pgbackrest) for the supabase cluster is TODO; this daily pg_dumpall
  # gives ~24h RPO as a safety net until that's wired.
  systemd.services.supabase-db-dump = {
    description = "daily pg_dumpall of the supabase PG17 cluster";

    after = [ "supabase-db.service" ];
    requires = [ "supabase-db.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "supabase-postgres";
    };

    path = [ pkgs.gzip ];

    script = ''
      ${pkgs.postgresql_17}/bin/pg_dumpall \
        -h /run/supabase-db -p 5433 -U postgres \
        | gzip > /var/lib/supabase/db/dump.sql.gz.tmp
      mv /var/lib/supabase/db/dump.sql.gz.tmp /var/lib/supabase/db/dump.sql.gz
    '';
  };

  systemd.timers.supabase-db-dump = {
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };

  # deploy straylight branding to forgejo custom assets
  systemd.tmpfiles.rules =
    let
      logo = ../../../design/straylight-logo-small.png;
    in
    [
      "d /var/lib/forgejo/custom/public/assets/img 0755 git git - -"
      "C /var/lib/forgejo/custom/public/assets/img/logo.png - git git - ${logo}"
      "C /var/lib/forgejo/custom/public/assets/img/favicon.png - git git - ${logo}"
    ];

  # ── Grafana (observability dashboards) ─────────────────────────────────────────
  # Fronted by nginx at grafana.s4.gl. ClickHouse datasource provisioned
  # declaratively. Dashboards compiled from Dhall → JSON → file provisioning.
  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3300;
        root_url = "https://grafana.s4.gl/";
        domain = "grafana.s4.gl";
      };

      security = {
        admin_user = "admin";
        admin_password = "$__file{/run/agenix/grafana-admin-password}";
        secret_key = "$__file{/run/agenix/grafana-admin-password}";
      };

      "auth.anonymous" = {
        enabled = true;
        org_role = "Viewer";
      };

      "auth.generic_oauth" = {
        enabled = true;
        name = "Kanidm";
        icon = "signin";
        client_id = "grafana";
        client_secret = "$__file{/run/agenix/grafana-oauth-secret}";
        scopes = "openid email profile groups";
        auth_url = "https://auth.s4.gl/ui/oauth2";
        token_url = "https://auth.s4.gl/oauth2/token";
        api_url = "https://auth.s4.gl/oauth2/openid/grafana/userinfo";
        use_pkce = true;
        allow_sign_up = true;
        # map kanidm groups to grafana roles
        role_attribute_path = "contains(groups[*], 'grafana_admins') && 'Admin' || 'Viewer'";
      };
    };

    # declarative datasource provisioning
    provision = {
      enable = true;

      datasources.settings.datasources = [
        {
          name = "ClickHouse";
          type = "grafana-clickhouse-datasource";
          uid = "clickhouse";
          access = "proxy";
          isDefault = true;
          jsonData = {
            host = "127.0.0.1";
            port = 9000;
            protocol = "native";
            defaultDatabase = "otel";
            username = "default";
          };
        }
      ];

      # dashboards from Dhall (rendered at build time)
      dashboards.settings.providers = [
        {
          name = "fleet";
          type = "file";
          options.path = "/etc/grafana/dashboards";
          options.foldersFromFilesStructure = true;
        }
      ];
    };
  };

  # install the clickhouse grafana plugin
  services.grafana.declarativePlugins = [
    pkgs.grafanaPlugins.grafana-clickhouse-datasource
  ];

  # render dashboards from Dhall → JSON (type-safe, auto-layout)
  environment.etc =
    let
      grafanaDir = ../../../modules/flake/grafana;
      dashboardDir = "${grafanaDir}/dashboards";
      dhallFiles = builtins.filter (n: builtins.match ".*\\.dhall" n != null) (
        builtins.attrNames (builtins.readDir dashboardDir)
      );
      renderDashboard =
        file:
        let
          name = builtins.replaceStrings [ ".dhall" ] [ "" ] file;
        in
        pkgs.runCommand "grafana-dashboard-${name}.json"
          {
            nativeBuildInputs = [ pkgs.dhall-json ];
          }
          ''
            dhall-to-json --file ${grafanaDir}/dashboards/${file} > $out
          '';
    in
    builtins.listToAttrs (
      map (
        file:
        let
          name = builtins.replaceStrings [ ".dhall" ] [ "" ] file;
        in
        {
          name = "grafana/dashboards/${name}.json";
          value.source = renderDashboard file;
        }
      ) dhallFiles
    );

  age.secrets.grafana-admin-password = {
    file = ../../../secrets/agenix/machines/grafana-admin-password.age;
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # ── ClickHouse (OLAP server + S3→R2 storage) ──────────────────────────────────

  # single server on watchtower; keepers on ultraviolence/guccimane/shimmer.
  # S3 disk to R2 = durable truth; local disk is reconstructible cache.
  hyper-modern-nixos.databases.clickhouse.server = {
    enable = true;
    s3.enable = true;
  };

  # ── OTel (observability spine) ───────────────────────────────────────────────

  # gateway (receives from fleet agents → writes to ClickHouse) + local agent
  hyper-modern-nixos.observability.otel = {
    gateway.enable = true;

    agent = {
      enable = true;
      scrapeTargets = [
        "127.0.0.1:9153" # coredns
        "127.0.0.1:3001" # postgrest (admin)
        "127.0.0.1:9363" # clickhouse
        "127.0.0.1:3200" # forgejo
      ];

      logPaths = [
        "/var/log/pgbackrest/supabase-*.log"
      ];
    };
  };

  # ── Identity (user registry → kanidm + SSH + grafana) ─────────────────────────
  hyper-modern-nixos.identity = {
    enable = true;
    kanidm = true; # this host is the IdP — provision users/groups here
  };

  # ── Kanidm (identity provider) ─────────────────────────────────────────────
  # Sovereign IdP — WebAuthn/passkey-first, OIDC provider for the fleet.
  # SQLite-backed (Litestream → R2 for backup). Fronted by nginx at auth.s4.gl.
  # Self-signed TLS for the loopback (nginx terminates real TLS at the edge).
  services.kanidm = {
    package = pkgs.kanidm_1_9.withSecretProvisioning;

    server.enable = true;

    server.settings = {
      origin = "https://auth.s4.gl";
      domain = "s4.gl";
      bindaddress = "127.0.0.1:8443";
      ldapbindaddress = null;
      log_level = "info";
      role = "WriteReplica";

      # self-signed cert for loopback (nginx handles real TLS)
      tls_chain = "/var/lib/kanidm/tls/chain.pem";
      tls_key = "/var/lib/kanidm/tls/key.pem";

      online_backup = {
        path = "/var/lib/kanidm/backups/";
        schedule = "0 2 * * *"; # daily at 2am
        versions = 7;
      };
    };

    # provisioning: users/groups from the registry, OIDC clients here (host-specific secrets)
    provision = {
      enable = true;
      adminPasswordFile = "/run/agenix/kanidm-admin-password";
      idmAdminPasswordFile = "/run/agenix/kanidm-admin-password";

      # groups + persons driven by hyper-modern-nixos.identity (from users.dhall)

      systems.oauth2.forgejo = {
        displayName = "// straylight // git //";
        originUrl = "https://git.s4.gl/user/oauth2/kanidm/callback";
        originLanding = "https://git.s4.gl/";
        basicSecretFile = "/run/agenix/kanidm-forgejo-secret";
        preferShortUsername = true;
        allowInsecureClientDisablePkce = true;
        # scopeMaps driven by identity module
      };

      systems.oauth2.grafana = {
        displayName = "// straylight // grafana //";
        originUrl = "https://grafana.s4.gl/login/generic_oauth";
        originLanding = "https://grafana.s4.gl/";
        basicSecretFile = "/run/agenix/kanidm-grafana-secret";
        preferShortUsername = true;
        allowInsecureClientDisablePkce = true;
        scopeMaps.fleet_users = [
          "openid"
          "email"
          "profile"
          "groups"
        ];
      };
    };
  };

  # generate self-signed TLS cert for kanidm's loopback listener (one-time)
  systemd.services.kanidm-tls-init = {
    description = "generate self-signed TLS cert for kanidm";
    before = [ "kanidm.service" ];
    requiredBy = [ "kanidm.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "kanidm";
      Group = "kanidm";
      StateDirectory = "kanidm/tls";
      RemainAfterExit = true;
    };

    path = [ pkgs.openssl ];

    script = ''
      if [ ! -f /var/lib/kanidm/tls/key.pem ]; then
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
          -keyout /var/lib/kanidm/tls/key.pem \
          -out /var/lib/kanidm/tls/chain.pem \
          -days 3650 -nodes \
          -subj "/CN=localhost"
        chmod 0640 /var/lib/kanidm/tls/key.pem
        chmod 0644 /var/lib/kanidm/tls/chain.pem
      fi
    '';
  };

  # kanidm secrets (admin password + forgejo oauth2 secret)
  age.secrets.kanidm-admin-password = {
    file = ../../../secrets/agenix/machines/kanidm-admin-password.age;
    owner = "kanidm";
    group = "kanidm";
    mode = "0400";
  };

  age.secrets.kanidm-forgejo-secret = {
    file = ../../../secrets/agenix/machines/kanidm-forgejo-secret.age;
    owner = "kanidm";
    group = "kanidm";
    mode = "0400";
  };
  # same secret, two paths: kanidm needs it for provisioning, grafana for OIDC auth
  age.secrets.kanidm-grafana-secret = {
    file = ../../../secrets/agenix/machines/kanidm-grafana-secret.age;
    owner = "kanidm";
    group = "kanidm";
    mode = "0400";
  };
  age.secrets.grafana-oauth-secret = {
    file = ../../../secrets/agenix/machines/kanidm-grafana-secret.age;
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # ── Litestream (continuous SQLite replication → R2) ──────────────────────────

  # Replicates kanidm's SQLite to R2 for near-zero RPO disaster recovery.
  # Runs as the kanidm user so it can read the WAL. Starts before kanidm and
  # stays alive as a sidecar, streaming WAL changes continuously.
  systemd.services.litestream = {
    description = "litestream SQLite replication (kanidm → R2)";

    after = [
      "network.target"
      "kanidm-tls-init.service"
    ];

    before = [ "kanidm.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "kanidm";
      Group = "kanidm";
      ExecStart = "${pkgs.litestream}/bin/litestream replicate -config /run/litestream/config.yml";
      EnvironmentFile = "/run/agenix/litestream-r2-env";
      Restart = "on-failure";
      RestartSec = "10s";

      # litestream needs to write its runtime config
      RuntimeDirectory = "litestream";
      RuntimeDirectoryMode = "0750";
    };

    # generate config from env at start (keeps secrets out of the nix store)
    preStart = ''
      cat > /run/litestream/config.yml <<EOF
      dbs:
        - path: /var/lib/kanidm/kanidm.db
          replicas:
            - type: s3
              bucket: straylight-litestream
              path: kanidm
              endpoint: https://6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com
              force-path-style: true
      EOF
    '';
  };

  age.secrets.litestream-r2-env = {
    file = ../../../secrets/agenix/machines/litestream-r2-env.age;
    owner = "kanidm";
    group = "kanidm";
    mode = "0400";
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
    services.attic.port = 8080; # → atticd (the monolithic backend)
    services.git.port = 3200; # → forgejo

    services.auth = {
      # → kanidm (HTTPS loopback)
      port = 8443;
      scheme = "https";
    };

    services.ch.port = 8123; # → clickhouse play UI / HTTP API
    services.grafana.port = 3300; # → grafana
  };

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

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
    useSupabaseDb = true;
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

    paths = [
      "/home"
      "/var/lib/forgejo" # git repos + custom assets
      "/var/lib/kanidm" # IdP state (also covered by litestream)
      "/var/lib/supabase/db/dump.sql.gz" # PG17 daily logical dump
    ];
  };

  system.stateVersion = "25.05";
}
