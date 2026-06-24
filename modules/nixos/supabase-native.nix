# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                       // hyper-modern-nixos // supabase-native
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#   "the street finds its own uses for things"
#
# Native (daemon-free) Supabase. No Docker. Each service is a systemd unit backed
# by a Nix-built binary. The DB is the supabase/postgres flake's PG17 + 112
# extensions, running as a second postgres instance on port 5433 (attic's PG16
# keeps 5432). GoTrue, PostgREST, imgproxy from nixpkgs. Kong is replaced by
# nginx location blocks in the existing reverse-proxy module.
#
# ── Coexistence with attic's PG16 ──────────────────────────────────────────────
# NixOS's `services.postgresql` is a singleton. We hand-roll a second systemd
# unit (supabase-db.service) with its own dataDir, port, unix socket, and user.
# The two clusters are fully independent.
#
# ── Init SQL ────────────────────────────────────────────────────────────────────
# The supabase DB needs specific roles + schema (roles.sql, jwt.sql, etc.) from
# the upstream docker/volumes/db/ tree. These are applied via a first-boot
# oneshot that checks for a sentinel before running. Subsequent boots skip init.
{
  config,
  lib,
  pkgs,
  flake ? null,
  ...
}:
let
  cfg = config.hyper-modern-nixos.supabase-native;

  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  # pinned upstream source (for init SQL + kong.yml template)
  src = if flake != null then flake.inputs.supabase else null;
  vol = "${src}/docker/volumes";

  # supabase-postgres flake: PG17 + 112 extensions
  supabasePg = flake.inputs.supabase-postgres.packages.${pkgs.system}."psql_17/bin";

  # runtime env dir (same split pattern as the container module)
  runtimeEnvDir = "/run/supabase/env";
  svcEnv = name: "${runtimeEnvDir}/${name}";

  # the supabase cluster's connection params (localhost, unix socket)
  pgPort = cfg.db.port;
  pgHost = "127.0.0.1";
  pgDb = "postgres";
  pgSocket = cfg.db.socketDir;
  pgDataDir = cfg.db.dataDir;
  pgUser = "supabase-postgres"; # system user for this cluster

  # ── OCI extraction (crane export → autopatchelf / node wrapper) ───────────
  oci = import ../../lib/oci.nix { inherit pkgs; };

  supabaseRealtime = oci.extractBin {
    name = "supabase-realtime";
    version = "2.102.3";
    image = "docker.io/supabase/realtime:v2.102.3";
    hash = "sha256-f3fRNDmg3C9PPHblt/viuXtLB3nud6WInYB0MxPjSi8=";
    appDir = "/app";
    entrypoint = "bin/realtime";
    runtimeInputs = with pkgs; [
      openssl
      ncurses
      zlib
      libgcc.lib
    ];
  };

  supabaseStorage = oci.extractBin {
    name = "supabase-storage";
    version = "1.60.4";
    image = "docker.io/supabase/storage-api:v1.60.4";
    hash = "sha256-JCpZ5fpGZ3PrFfYQCTMbb6RW1rZeFCei5KCkZYFsoAc=";
    appDir = "/app";
    entrypoint = "dist/start/server.js";
    isNode = true;
    nodePackage = pkgs.nodejs_22; # image uses 24 but 22 runs this fine
  };

  supabaseStudio = oci.extractBin {
    name = "supabase-studio";
    version = "2026.06.03";
    image = "docker.io/supabase/studio:2026.06.03-sha-0bca601";
    hash = "sha256-WClIhnjnZw741U5m1Bu9Md3xtwlsviqTBFBbQJ5JPXs=";
    appDir = "/app";
    entrypoint = "apps/studio/server.js";
    isNode = true;
    nodePackage = pkgs.nodejs_22;
  };
in
{
  options.hyper-modern-nixos.supabase-native = {
    enable = mkEnableOption "native (daemon-free) Supabase stack";

    environmentFile = mkOption {
      type = types.str;
      default = "/run/agenix/supabase-env";
      description = ''
        Decrypted env file carrying the secret bundle (JWT_SECRET, ANON_KEY,
        SERVICE_ROLE_KEY, POSTGRES_PASSWORD, SECRET_KEY_BASE, VAULT_ENC_KEY,
        PG_META_CRYPTO_KEY, DASHBOARD_*). Same file as the container module.
      '';
    };

    selfWireSecret = mkOption {
      type = types.bool;
      default = true;
      description = "Self-wire age.secrets.supabase-env from the in-repo .age file.";
    };

    publicUrl = mkOption {
      type = types.str;
      default = "http://localhost:8000";
      example = "https://studio.sju1.s4.gl";
      description = "Externally-reachable base URL.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/supabase";
      description = "Parent of the cluster (db/) and Storage (storage/) state.";
    };

    db = {
      port = mkOption {
        type = types.port;
        default = 5433;
        description = "Port for the supabase postgres instance (avoids attic's 5432).";
      };
      dataDir = mkOption {
        type = types.str;
        default = "/var/lib/supabase/db";
        description = "PGDATA for the supabase cluster.";
      };
      socketDir = mkOption {
        type = types.str;
        default = "/run/supabase-db";
        description = "Unix socket directory for the supabase cluster.";
      };
    };

    auth = {
      port = mkOption {
        type = types.port;
        default = 9999;
        description = "GoTrue API port.";
      };
    };

    rest = {
      port = mkOption {
        type = types.port;
        default = 3000;
        description = "PostgREST port.";
      };
      adminPort = mkOption {
        type = types.port;
        default = 3001;
        description = "PostgREST admin port (health checks).";
      };
    };

    imgproxy = {
      port = mkOption {
        type = types.port;
        default = 5001;
        description = "imgproxy port.";
      };
    };

    meta = {
      port = mkOption {
        type = types.port;
        default = 8085;
        description = "postgres-meta port (shifted from 8080 to avoid conflicts).";
      };
    };

    realtime = {
      port = mkOption {
        type = types.port;
        default = 4000;
        description = "Realtime (Phoenix) port.";
      };
    };

    storage = {
      port = mkOption {
        type = types.port;
        default = 5000;
        description = "Storage API port (shifted from 5000 if zot conflicts).";
      };
    };

    studio = {
      port = mkOption {
        type = types.port;
        default = 3100;
        description = "Studio (Next.js) port.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = src != null;
        message = ''
          hyper-modern-nixos.supabase-native needs the `flake` specialArg (for
          the pinned `supabase` input providing init SQL + config files).
        '';
      }
      {
        assertion = !(config.hyper-modern-nixos ? supabase && config.hyper-modern-nixos.supabase.enable);
        message = ''
          Both supabase (container) and supabase-native are enabled. Disable
          the container module first (hyper-modern-nixos.supabase.enable = false).
        '';
      }
    ];

    # ── Secret wiring ─────────────────────────────────────────────────────────
    age.secrets = mkIf cfg.selfWireSecret {
      supabase-env.file = flake.self + "/secrets/agenix/machines/supabase-env.age";
    };

    # ── State classification ──────────────────────────────────────────────────
    hyper-modern-nixos.state.dirs = {
      supabase-db = {
        path = cfg.db.dataDir;
        class = "authoritative";
      };
      supabase-storage = {
        path = "${cfg.dataDir}/storage";
        class = "authoritative";
      };
    };

    # ── System user for the supabase postgres cluster ─────────────────────────
    users.users.${pgUser} = {
      isSystemUser = true;
      group = pgUser;
      home = pgDataDir;
      description = "supabase postgres (port ${toString pgPort})";
    };
    users.groups.${pgUser} = { };

    # ── Directories ───────────────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
      "d ${pgDataDir} 0750 ${pgUser} ${pgUser} - -"
      "d ${pgSocket} 0755 ${pgUser} ${pgUser} - -"
      "d ${cfg.dataDir}/storage 0750 root root - -"
      "d ${runtimeEnvDir} 0700 root root - -"
    ];

    # ── supabase-env-split: same pattern as the container module ──────────────
    # sources the agenix bundle and writes per-service env files. The DB URLs now
    # point at localhost:${pgPort} (native) instead of the docker `db` alias.
    systemd.services.supabase-env-split = {
      description = "compose supabase per-service env files from the agenix bundle";
      after = [ "run-agenix.d.mount" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      restartTriggers = [ cfg.environmentFile ];
      script = ''
        set -euo pipefail
        umask 077
        if [ ! -r "${cfg.environmentFile}" ] || [ ! -s "${cfg.environmentFile}" ]; then
          echo "supabase-env-split: ${cfg.environmentFile} missing or empty" >&2
          exit 1
        fi
        # shellcheck disable=SC1090
        set -a; . "${cfg.environmentFile}"; set +a

        d="${runtimeEnvDir}"
        install -d -m 0700 "$d"

        # url <role> → postgres://<role>:<pw>@127.0.0.1:${toString pgPort}/postgres
        url() { printf 'postgres://%s:%s@${pgHost}:${toString pgPort}/${pgDb}' "$1" "$POSTGRES_PASSWORD"; }

        # db: cluster password (for init + health checks)
        printf '%s\n' \
          "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
          "PGPASSWORD=$POSTGRES_PASSWORD" > "$d/db"

        # auth (gotrue)
        printf '%s\n' \
          "GOTRUE_DATABASE_URL=$(url supabase_auth_admin)" \
          "DATABASE_URL=$(url supabase_auth_admin)" \
          "GOTRUE_JWT_SECRET=$JWT_SECRET" \
          "AUTH_JWT_SECRET=$JWT_SECRET" > "$d/auth"

        # rest (postgrest)
        printf '%s\n' \
          "PGRST_DB_URI=$(url authenticator)" \
          "PGRST_JWT_SECRET=$JWT_SECRET" \
          "PGRST_APP_SETTINGS_JWT_SECRET=$JWT_SECRET" > "$d/rest"

        # meta (postgres-meta)
        printf '%s\n' \
          "PG_META_DB_PASSWORD=$POSTGRES_PASSWORD" \
          "CRYPTO_KEY=$PG_META_CRYPTO_KEY" > "$d/meta"

        # realtime
        printf '%s\n' \
          "DB_PASSWORD=$POSTGRES_PASSWORD" \
          "API_JWT_SECRET=$JWT_SECRET" \
          "METRICS_JWT_SECRET=$JWT_SECRET" \
          "SECRET_KEY_BASE=$SECRET_KEY_BASE" > "$d/realtime"

        # storage
        printf '%s\n' \
          "DATABASE_URL=$(url supabase_storage_admin)" \
          "ANON_KEY=$ANON_KEY" \
          "SERVICE_KEY=$SERVICE_ROLE_KEY" \
          "AUTH_JWT_SECRET=$JWT_SECRET" > "$d/storage"

        # imgproxy: no secrets
        : > "$d/imgproxy"

        # studio
        printf '%s\n' \
          "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
          "PG_META_CRYPTO_KEY=$PG_META_CRYPTO_KEY" \
          "SUPABASE_ANON_KEY=$ANON_KEY" \
          "SUPABASE_SERVICE_KEY=$SERVICE_ROLE_KEY" \
          "AUTH_JWT_SECRET=$JWT_SECRET" > "$d/studio"

        # kong (used by the nginx gateway template — anon/service keys for header injection)
        printf '%s\n' \
          "SUPABASE_ANON_KEY=$ANON_KEY" \
          "SUPABASE_SERVICE_KEY=$SERVICE_ROLE_KEY" \
          "DASHBOARD_USERNAME=$DASHBOARD_USERNAME" \
          "DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD" > "$d/kong"

        chmod 0600 "$d"/*
      '';
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  DB: native PG17 (supabase-postgres flake) on port ${toString pgPort}
    # ══════════════════════════════════════════════════════════════════════════════

    systemd.services.supabase-db = {
      description = "supabase postgresql 17 (port ${toString pgPort})";
      after = [
        "network.target"
        "supabase-env-split.service"
      ];
      requires = [ "supabase-env-split.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PGDATA = pgDataDir;
        PGPORT = toString pgPort;
        PGDATABASE = pgDb;
      };

      serviceConfig = {
        Type = "notify";
        User = pgUser;
        Group = pgUser;
        RuntimeDirectory = "supabase-db";
        EnvironmentFile = svcEnv "db";

        ExecStartPre =
          let
            initScript = pkgs.writeShellScript "supabase-db-init" ''
              set -euo pipefail
              export PATH="${
                lib.makeBinPath [
                  supabasePg
                  pkgs.coreutils
                ]
              }:$PATH"

              if [ ! -f "${pgDataDir}/PG_VERSION" ]; then
                echo "// supabase-db // initializing cluster at ${pgDataDir}"
                initdb \
                  --pgdata="${pgDataDir}" \
                  --username=postgres \
                  --encoding=UTF8 \
                  --locale=C \
                  --auth-local=peer \
                  --auth-host=md5

                # configure: listen on port ${toString pgPort}, accept localhost md5
                cat >> "${pgDataDir}/postgresql.conf" <<CONF

              # ── supabase-native managed ──
              port = ${toString pgPort}
              unix_socket_directories = '${pgSocket}'
              listen_addresses = '127.0.0.1'
              shared_preload_libraries = 'pg_net, pgsodium, pg_stat_statements, pgaudit, pg_cron, pgjwt, supautils'
              log_min_messages = fatal
              # pgsodium needs its key in a file
              pgsodium.getkey_script = '${pgDataDir}/pgsodium_getkey.sh'
              CONF

                # pg_hba: local peer + md5 from localhost
                cat > "${pgDataDir}/pg_hba.conf" <<HBA
              local   all   all                peer
              host    all   all   127.0.0.1/32  md5
              host    all   all   ::1/128       md5
              HBA

                # pgsodium getkey script (generates a key on first call, persists it)
                cat > "${pgDataDir}/pgsodium_getkey.sh" <<'GETKEY'
              #!/bin/sh
              KEY_FILE="''${PGDATA}/pgsodium_root.key"
              if [ ! -f "$KEY_FILE" ]; then
                head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n' > "$KEY_FILE"
                chmod 0600 "$KEY_FILE"
              fi
              cat "$KEY_FILE"
              GETKEY
                chmod 0750 "${pgDataDir}/pgsodium_getkey.sh"

                echo "// supabase-db // cluster initialized, starting for init SQL"
              fi
            '';
          in
          "!${initScript}";

        ExecStart = "${supabasePg}/bin/postgres -D ${pgDataDir}";

        # hardening
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          pgDataDir
          pgSocket
          "/run/supabase-db"
        ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # ── init SQL: apply roles/schema on first boot ────────────────────────────
    # runs ONCE (sentinel file), ordered after supabase-db is ready.
    systemd.services.supabase-db-init-sql = {
      description = "supabase db: apply init SQL (first boot only)";
      after = [ "supabase-db.service" ];
      requires = [ "supabase-db.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = pgUser;
        RemainAfterExit = true;
        EnvironmentFile = svcEnv "db";
      };

      path = [
        supabasePg
        pkgs.coreutils
      ];

      script = ''
        set -euo pipefail
        SENTINEL="${pgDataDir}/.supabase-init-done"
        if [ -f "$SENTINEL" ]; then
          echo "// supabase-db-init-sql // already initialized, skipping"
          exit 0
        fi

        echo "// supabase-db-init-sql // applying init SQL to port ${toString pgPort}"
        PSQL="psql -h ${pgSocket} -p ${toString pgPort} -U postgres -d ${pgDb} -v ON_ERROR_STOP=1"

        # set the superuser password first
        $PSQL -c "ALTER ROLE postgres WITH PASSWORD '$POSTGRES_PASSWORD';"

        # apply the init scripts in the correct order (matches upstream docker-entrypoint)
        # 1. _supabase schema (internal bookkeeping)
        $PSQL -f "${vol}/db/_supabase.sql"

        # 2. roles (creates all supabase_* roles + authenticator + anon + service_role)
        $PSQL -f "${vol}/db/roles.sql"

        # 3. jwt helpers
        $PSQL -f "${vol}/db/jwt.sql"

        # 4. realtime schema
        $PSQL -f "${vol}/db/realtime.sql"

        # 5. webhooks
        $PSQL -f "${vol}/db/webhooks.sql"

        # 6. logs (analytics schema)
        $PSQL -f "${vol}/db/logs.sql"

        # 7. pooler (supavisor schema)
        $PSQL -f "${vol}/db/pooler.sql"

        # set passwords for the key service roles
        $PSQL <<SQL
          ALTER ROLE supabase_auth_admin WITH PASSWORD '$POSTGRES_PASSWORD';
          ALTER ROLE supabase_storage_admin WITH PASSWORD '$POSTGRES_PASSWORD';
          ALTER ROLE supabase_admin WITH PASSWORD '$POSTGRES_PASSWORD';
          ALTER ROLE authenticator WITH PASSWORD '$POSTGRES_PASSWORD';
        SQL

        touch "$SENTINEL"
        echo "// supabase-db-init-sql // done"
      '';
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  GoTrue (auth) — from nixpkgs
    # ══════════════════════════════════════════════════════════════════════════════

    systemd.services.supabase-auth = {
      description = "supabase auth (gotrue)";
      after = [
        "supabase-db-init-sql.service"
        "supabase-env-split.service"
      ];
      requires = [
        "supabase-db.service"
        "supabase-env-split.service"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        GOTRUE_API_HOST = "127.0.0.1";
        GOTRUE_API_PORT = toString cfg.auth.port;
        API_EXTERNAL_URL = cfg.publicUrl;
        GOTRUE_DB_DRIVER = "postgres";
        GOTRUE_SITE_URL = cfg.publicUrl;
        GOTRUE_JWT_ADMIN_ROLES = "service_role";
        GOTRUE_JWT_AUD = "authenticated";
        GOTRUE_JWT_DEFAULT_GROUP_NAME = "authenticated";
        GOTRUE_JWT_EXP = "3600";
        GOTRUE_JWT_ISSUER = "${cfg.publicUrl}/auth/v1";
        GOTRUE_EXTERNAL_EMAIL_ENABLED = "true";
        GOTRUE_MAILER_AUTOCONFIRM = "true";
        GOTRUE_DISABLE_SIGNUP = "false";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.gotrue-supabase}/bin/auth";
        EnvironmentFile = svcEnv "auth";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";

        # hardening
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  PostgREST — from nixpkgs
    # ══════════════════════════════════════════════════════════════════════════════

    systemd.services.supabase-rest = {
      description = "supabase rest (postgrest)";
      after = [
        "supabase-db-init-sql.service"
        "supabase-env-split.service"
      ];
      requires = [
        "supabase-db.service"
        "supabase-env-split.service"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PGRST_DB_SCHEMAS = "public,storage,graphql_public";
        PGRST_DB_ANON_ROLE = "anon";
        PGRST_DB_USE_LEGACY_GUCS = "false";
        PGRST_SERVER_PORT = toString cfg.rest.port;
        PGRST_ADMIN_SERVER_PORT = toString cfg.rest.adminPort;
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.postgrest}/bin/postgrest";
        EnvironmentFile = svcEnv "rest";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  imgproxy — from nixpkgs
    # ══════════════════════════════════════════════════════════════════════════════

    systemd.services.supabase-imgproxy = {
      description = "supabase imgproxy (image transforms)";
      after = [ "supabase-env-split.service" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        IMGPROXY_BIND = "127.0.0.1:${toString cfg.imgproxy.port}";
        IMGPROXY_LOCAL_FILESYSTEM_ROOT = "${cfg.dataDir}/storage";
        IMGPROXY_USE_ETAG = "true";
        IMGPROXY_AUTO_WEBP = "true";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.imgproxy}/bin/imgproxy";
        EnvironmentFile = svcEnv "imgproxy";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectHome = true;
        ProtectSystem = "strict";
        ReadOnlyPaths = [ "${cfg.dataDir}/storage" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  API Gateway: nginx locations (replaces Kong)
    # ══════════════════════════════════════════════════════════════════════════════
    #
    # Kong's role was purely routing + key injection. Our existing nginx reverse
    # proxy (wildcard cert on *.sju1.s4.gl) can do this natively. The routing
    # table from kong.yml becomes location blocks:
    #
    #   /auth/v1/*  → GoTrue (port 9999)
    #   /rest/v1/*  → PostgREST (port 3000)
    #   /realtime/* → Realtime (port 4000) [WebSocket upgrade]
    #   /storage/v1/* → Storage (port 5000)
    #   /pg/*       → postgres-meta (port 8085)
    #   /           → Studio (port 3100)
    #
    # NOTE: this is wired via the reverse-proxy module's `services` option or
    # directly as nginx virtualHosts. For now we declare the virtualHost here
    # and the watchtower config just points `services.studio.port` at our
    # gateway port or we take over the vhost entirely.

    # The gateway port that the existing reverse-proxy proxies to. We use a
    # simple nginx server block on loopback as the Supabase API gateway,
    # replicating Kong's declarative routing. This is internal-only (the
    # external-facing nginx in reverse-proxy.nix terminates TLS and proxies
    # studio.sju1.s4.gl → this).
    services.nginx.enable = true;

    services.nginx.virtualHosts."supabase-gateway" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 8000;
        }
      ];
      # no TLS here — this is the internal gateway (the reverse-proxy does TLS)

      locations = {
        # auth
        "/auth/v1/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.auth.port}/";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Host $host;
          '';
        };

        # rest (postgrest)
        "/rest/v1/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.rest.port}/";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
          '';
        };

        # realtime (websocket)
        "/realtime/v1/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.realtime.port}/";
          extraConfig = ''
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
          '';
        };

        # storage
        "/storage/v1/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.storage.port}/";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
            client_max_body_size 50m;
          '';
        };

        # postgres-meta (studio backend)
        "/pg/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.meta.port}/";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
          '';
        };

        # studio (dashboard) — catch-all
        "/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.studio.port}/";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
          '';
        };
      };
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  postgres-meta — native (buildNpmPackage)
    # ══════════════════════════════════════════════════════════════════════════════

    systemd.services.supabase-meta = {
      description = "supabase postgres-meta (Studio backend)";
      after = [
        "supabase-db-init-sql.service"
        "supabase-env-split.service"
      ];
      requires = [
        "supabase-db.service"
        "supabase-env-split.service"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PG_META_PORT = toString cfg.meta.port;
        PG_META_HOST = "127.0.0.1";
        PG_META_DB_HOST = pgHost;
        PG_META_DB_PORT = toString pgPort;
        PG_META_DB_NAME = pgDb;
        PG_META_DB_USER = "postgres";
        # PG_META_DB_PASSWORD + CRYPTO_KEY from env file
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.callPackage ../../packages/supabase-postgres-meta { }}/bin/postgres-meta";
        EnvironmentFile = svcEnv "meta";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  Realtime — BEAM release extracted from OCI via crane
    # ══════════════════════════════════════════════════════════════════════════════

    systemd.services.supabase-realtime = {
      description = "supabase realtime (BEAM, crane-extracted)";
      after = [
        "supabase-db-init-sql.service"
        "supabase-env-split.service"
      ];
      requires = [
        "supabase-db.service"
        "supabase-env-split.service"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PORT = toString cfg.realtime.port;
        DB_HOST = pgHost;
        DB_PORT = toString pgPort;
        DB_USER = "supabase_admin";
        DB_NAME = pgDb;
        DB_AFTER_CONNECT_QUERY = "SET search_path TO _realtime";
        DB_ENC_KEY = "supabaserealtime";
        ERL_AFLAGS = "-proto_dist inet_tcp";
        DNS_NODES = "''";
        APP_NAME = "realtime";
        SEED_SELF_HOST = "true";
        RUN_JANITOR = "true";
        PHX_SERVER = "true";
        # the BEAM release needs to know where ERTS lives
        RELEASE_ROOT = "${supabaseRealtime}/app";
        RELEASE_TMP = "/tmp/supabase-realtime";
        ERL_CRASH_DUMP = "/tmp/supabase-realtime/erl_crash.dump";
      };

      serviceConfig = {
        Type = "simple";
        EnvironmentFile = svcEnv "realtime";
        DynamicUser = true;
        RuntimeDirectory = "supabase-realtime";
        StateDirectory = "supabase-realtime";

        ExecStartPre =
          let
            migrateScript = pkgs.writeShellScript "supabase-realtime-migrate" ''
              set -euo pipefail
              mkdir -p /tmp/supabase-realtime
              ${supabaseRealtime}/bin/supabase-realtime eval 'Realtime.Release.migrate()'
              ${supabaseRealtime}/bin/supabase-realtime eval 'Realtime.Release.seeds(Realtime.Repo)'
            '';
          in
          "+${migrateScript}";

        ExecStart = "${supabaseRealtime}/bin/supabase-realtime start";
        Restart = "on-failure";
        RestartSec = "5s";

        # hardening
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "/tmp/supabase-realtime" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  Storage — Node.js app extracted from OCI via crane
    # ══════════════════════════════════════════════════════════════════════════════

    systemd.services.supabase-storage = {
      description = "supabase storage (Node.js, crane-extracted)";
      after = [
        "supabase-db-init-sql.service"
        "supabase-env-split.service"
        "supabase-rest.service"
        "supabase-imgproxy.service"
      ];
      requires = [
        "supabase-db.service"
        "supabase-env-split.service"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        SERVER_PORT = toString cfg.storage.port;
        POSTGREST_URL = "http://127.0.0.1:${toString cfg.rest.port}";
        STORAGE_PUBLIC_URL = cfg.publicUrl;
        REQUEST_ALLOW_X_FORWARDED_PATH = "true";
        FILE_SIZE_LIMIT = "52428800";
        STORAGE_BACKEND = "file";
        FILE_STORAGE_BACKEND_PATH = "${cfg.dataDir}/storage";
        ENABLE_IMAGE_TRANSFORMATION = "true";
        IMGPROXY_URL = "http://127.0.0.1:${toString cfg.imgproxy.port}";
        TENANT_ID = "stub";
        REGION = "stub";
        GLOBAL_S3_BUCKET = "stub";
        NODE_ENV = "production";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${supabaseStorage}/bin/supabase-storage";
        EnvironmentFile = svcEnv "storage";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "${cfg.dataDir}/storage" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  Studio — Next.js app extracted from OCI via crane
    # ══════════════════════════════════════════════════════════════════════════════

    systemd.services.supabase-studio = {
      description = "supabase studio (Next.js, crane-extracted)";
      after = [
        "supabase-meta.service"
        "supabase-env-split.service"
      ];
      requires = [
        "supabase-meta.service"
        "supabase-env-split.service"
      ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        HOSTNAME = "127.0.0.1";
        PORT = toString cfg.studio.port;
        STUDIO_PG_META_URL = "http://127.0.0.1:${toString cfg.meta.port}";
        POSTGRES_HOST = pgHost;
        POSTGRES_PORT = toString pgPort;
        POSTGRES_DB = pgDb;
        POSTGRES_USER_READ_WRITE = "postgres";
        DEFAULT_ORGANIZATION_NAME = "Default Organization";
        DEFAULT_PROJECT_NAME = "Default Project";
        SUPABASE_URL = "http://127.0.0.1:8000";
        SUPABASE_PUBLIC_URL = cfg.publicUrl;
        PGRST_DB_SCHEMAS = "public,storage,graphql_public";
        NODE_ENV = "production";
        NEXT_TELEMETRY_DISABLED = "1";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${supabaseStudio}/bin/supabase-studio";
        EnvironmentFile = svcEnv "studio";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}
