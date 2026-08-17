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

  # supabase-postgres flake: use the slim bundle (fewer extensions, avoids the
  # wrappers installCheck hang). Falls back to the full bundle when the cache is
  # warm. The slim bundle has all the core supabase extensions (pgsodium, pg_net,
  # pgjwt, pg_graphql, pgvector, etc.) minus the heavy FDW wrappers.
  supabasePg = flake.inputs.supabase-postgres.packages.${pkgs.stdenv.hostPlatform.system}."psql_17_slim/bin";

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
    nodePackage = pkgs.nodejs_24;
    # fs-xattr native addon was built against musl (Alpine container)
    runtimeInputs = [ pkgs.musl ];
  };

  supabaseStudio = pkgs.callPackage ../../packages/supabase-studio { };
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
      tailnet = {
        enable = mkEnableOption ''
          expose the supabase PG17 cluster on the tailscale interface so
          fleet replicas (attic api-servers, etc.) can connect via md5 auth.
        '';
        interface = mkOption {
          type = types.str;
          default = "tailscale0";
          description = "Network interface to open the port on.";
        };
        cidrs = mkOption {
          type = types.listOf types.str;
          default = [
            "100.64.0.0/10"
            "fd7a:115c:a1e0::/48"
          ];
          description = "Tailnet CIDRs allowed md5-auth access.";
        };
      };

      # ── PITR (pgbackrest → R2) ───────────────────────────────────────────────
      pitr = {
        enable = mkEnableOption "continuous WAL archiving via pgbackrest → R2 for the PG17 cluster";
        stanza = mkOption {
          type = types.str;
          default = "supabase";
          description = "pgbackrest stanza name for this cluster.";
        };
        environmentFile = mkOption {
          type = types.nullOr types.str;
          default = "/run/agenix/pgbackrest-r2-env";
          description = "Env file with PGBACKREST_REPO1_S3_KEY[_SECRET].";
        };
        s3 = {
          bucket = mkOption {
            type = types.str;
            default = "straylight-pg-pitr";
            description = "R2 bucket for WAL + base backups.";
          };
          endpoint = mkOption {
            type = types.str;
            default = "https://6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com";
            description = "S3 endpoint.";
          };
          region = mkOption {
            type = types.str;
            default = "us-east-1";
            description = "S3 region (R2 ignores but pgbackrest requires).";
          };
        };
      };

      # ── additional databases (beyond supabase's own `postgres`) ───────────
      # declare databases that should be created in this cluster. Each gets a
      # role of the same name, owns the database, and has its password set from
      # an agenix secret. This is the seam for migrating atticd/forgejo/etc.
      # into the unified PG17 cluster.
      databases = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              passwordSecret = mkOption {
                type = types.str;
                description = "agenix secret name containing the role password.";
                example = "atticd-rs256";
              };
              passwordVar = mkOption {
                type = types.str;
                default = "PGPASSWORD";
                description = "env var within the secret holding the password.";
              };
              rawPassword = mkOption {
                type = types.bool;
                default = false;
                description = "if true, the secret file contains the raw password (not KEY=VAL).";
              };
              migrate = mkOption {
                type = types.submodule {
                  options = {
                    enable = mkOption {
                      type = types.bool;
                      default = false;
                      description = ''
                        One-time migration: pg_dump from an old cluster and pg_restore
                        into the supabase PG17 cluster. Sentinel-guarded (runs once).
                      '';
                    };
                    sourcePort = mkOption {
                      type = types.port;
                      default = 5432;
                      description = "Port of the old cluster to dump from.";
                    };
                    sourceUser = mkOption {
                      type = types.str;
                      default = "postgres";
                      description = "User to connect as on the old cluster (needs peer auth).";
                    };
                    sourceSocketDir = mkOption {
                      type = types.str;
                      default = "/run/postgresql";
                      description = "Unix socket dir of the old cluster.";
                    };
                  };
                };
                default = { };
                description = "One-time migration settings from an old PG cluster.";
              };
            };
          }
        );
        default = { };
        example = {
          atticd = {
            passwordSecret = "atticd-rs256";
            passwordVar = "PGPASSWORD";
            migrate.enable = true;
          };
        };
        description = ''
          Additional databases to create in the supabase PG17 cluster. Each key
          becomes a database AND a role (with ensureDBOwnership). The role password
          is set from the named agenix secret. Clients connect via:
            postgresql://<name>@localhost:${"\${db.port}"}/<name>
          with PGPASSWORD from the same secret.
        '';
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
        default = 5010;
        description = "Storage API port (5010 to avoid zot on 5000).";
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
    age.secrets =
      (lib.optionalAttrs cfg.selfWireSecret {
        supabase-env.file = flake.self + "/secrets/agenix/machines/supabase-env.age";
      })
      // (lib.optionalAttrs cfg.db.pitr.enable {
        pgbackrest-r2-env = {
          file = flake.self + "/secrets/agenix/machines/pgbackrest-r2-env.age";
          group = pgUser;
          mode = "0440";
        };
      })
      // (lib.optionalAttrs (cfg.db.databases != { }) (
        lib.mapAttrs' (
          _dbName: spec:
          lib.nameValuePair spec.passwordSecret {
            group = pgUser;
            mode = "0440";
          }
        ) cfg.db.databases
      ));

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
      "d ${cfg.dataDir} 0755 root root - -"
      "d ${pgDataDir} 0700 ${pgUser} ${pgUser} - -"
      "d ${pgSocket} 0755 ${pgUser} ${pgUser} - -"
      "d ${cfg.dataDir}/storage 0750 root root - -"
      "d ${runtimeEnvDir} 0700 root root - -"
    ]
    ++ lib.optionals cfg.db.pitr.enable [
      "d /var/log/pgbackrest 0750 ${pgUser} ${pgUser} - -"
      "d /var/lib/pgbackrest 0750 ${pgUser} ${pgUser} - -"
      "d /var/lib/pgbackrest/spool 0750 ${pgUser} ${pgUser} - -"
      "d /run/pgbackrest-supabase 0750 ${pgUser} ${pgUser} - -"
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
        Type = "simple";
        User = pgUser;
        Group = pgUser;
        RuntimeDirectory = "supabase-db";
        EnvironmentFile = [ (svcEnv "db") ] ++ lib.optional cfg.db.pitr.enable cfg.db.pitr.environmentFile;

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

                # configure the cluster
                {
                  echo ""
                  echo "# ── supabase-native managed ──"
                  echo "port = ${toString pgPort}"
                  echo "unix_socket_directories = '${pgSocket}'"
                  echo "listen_addresses = '${if cfg.db.tailnet.enable then "*" else "127.0.0.1"}'"
                  echo "shared_preload_libraries = 'pg_net, pgsodium, pg_stat_statements, pgaudit, pg_cron, supautils'"
                  echo "log_min_messages = fatal"
                  echo "pgsodium.getkey_script = '${pgDataDir}/pgsodium_getkey.sh'"
                  echo "include_dir = 'conf.d'"
                } >> "${pgDataDir}/postgresql.conf"

                mkdir -p "${pgDataDir}/conf.d"

                # pg_hba: local peer (with ident map) + md5 from localhost + tailnet
                {
                  echo "local   all   postgres           peer map=supabase"
                  echo "local   all   all                peer"
                  echo "host    all   all   127.0.0.1/32  md5"
                  echo "host    all   all   ::1/128       md5"
                  ${lib.concatMapStringsSep "\n" (cidr: ''
                    echo "host    all   all   ${cidr}  md5"
                  '') (lib.optionals cfg.db.tailnet.enable cfg.db.tailnet.cidrs)}
                } > "${pgDataDir}/pg_hba.conf"

                # pg_ident: map system user → PG role postgres
                {
                  echo "supabase   ${pgUser}   postgres"
                } > "${pgDataDir}/pg_ident.conf"

                # pgsodium getkey script
                {
                  echo '#!/bin/sh'
                  echo 'KEY_FILE="''${PGDATA}/pgsodium_root.key"'
                  echo 'if [ ! -f "$KEY_FILE" ]; then'
                  echo '  head -c 32 /dev/urandom | od -A n -t x1 | tr -d '"'"' \n'"'"' > "$KEY_FILE"'
                  echo '  chmod 0600 "$KEY_FILE"'
                  echo 'fi'
                  echo 'cat "$KEY_FILE"'
                } > "${pgDataDir}/pgsodium_getkey.sh"
                chmod 0750 "${pgDataDir}/pgsodium_getkey.sh"

                echo "// supabase-db // cluster initialized, starting for init SQL"
              fi
            '';
            tailnetConfScript = pkgs.writeShellScript "supabase-db-tailnet-conf" ''
                            set -euo pipefail
                            mkdir -p "${pgDataDir}/conf.d"

                            # ensure include_dir is set (existing clusters may lack it)
                            if ! grep -q "^include_dir" "${pgDataDir}/postgresql.conf"; then
                              echo "include_dir = 'conf.d'" >> "${pgDataDir}/postgresql.conf"
                            fi

                            # override listen_addresses via conf.d (last value wins)
                            cat > "${pgDataDir}/conf.d/tailnet.conf" <<'CONF'
              # managed by supabase-native (tailnet exposure)
              listen_addresses = '${if cfg.db.tailnet.enable then "*" else "127.0.0.1"}'
              CONF

                            # PITR: WAL archiving config
                            ${lib.optionalString cfg.db.pitr.enable ''
                                                          cat > "${pgDataDir}/conf.d/pitr.conf" <<'PITR'
                              # managed by supabase-native (pgbackrest PITR)
                              archive_mode = on
                              archive_command = '${pkgs.pgbackrest}/bin/pgbackrest --config=/etc/pgbackrest/pgbackrest-supabase.conf --stanza=${cfg.db.pitr.stanza} --log-level-file=info --log-path=/var/log/pgbackrest --lock-path=/run/pgbackrest-supabase archive-push %p'
                              wal_level = replica
                              max_wal_senders = 3
                              archive_timeout = 60
                              PITR
                            ''}

                            # ensure pg_ident maps supabase-postgres → both postgres and supabase_admin
                            {
                              echo "supabase   ${pgUser}   postgres"
                              echo "supabase   ${pgUser}   supabase_admin"
                            } > "${pgDataDir}/pg_ident.conf"

                            # rewrite pg_hba with current tailnet cidrs
                            {
                              echo "local   all   postgres           peer map=supabase"
                              echo "local   all   supabase_admin     peer map=supabase"
                              echo "local   all   all                peer"
                              echo "host    all   all   127.0.0.1/32  md5"
                              echo "host    all   all   ::1/128       md5"
                              ${lib.concatMapStringsSep "\n" (cidr: ''
                                echo "host    all   all   ${cidr}  md5"
                              '') (lib.optionals cfg.db.tailnet.enable cfg.db.tailnet.cidrs)}
                            } > "${pgDataDir}/pg_hba.conf"
            '';
          in
          [
            "!${initScript}"
            "!${tailnetConfScript}"
          ];

        ExecStart = "${supabasePg}/bin/postgres -D ${pgDataDir}";

        # readiness: dependent services wait for this via After=, so we need
        # postgres to be accepting connections before systemd considers us started.
        # Type=simple means ExecStart returns immediately; the ExecStartPost
        # pg_isready loop ensures the socket is up before dependents proceed.
        ExecStartPost =
          let
            waitScript = pkgs.writeShellScript "supabase-db-wait" ''
              for i in $(seq 1 30); do
                ${supabasePg}/bin/pg_isready -h 127.0.0.1 -p ${toString pgPort} -q && exit 0
                sleep 1
              done
              echo "supabase-db: timed out waiting for readiness" >&2
              exit 1
            '';
          in
          "${waitScript}";

        # hardening
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          pgDataDir
          pgSocket
          "/run/supabase-db"
        ]
        ++ lib.optionals cfg.db.pitr.enable [
          "/var/log/pgbackrest"
          "/run/pgbackrest-supabase"
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

        # wait for postgres to be ready (Type=simple, no sd_notify)
        for i in $(seq 1 30); do
          pg_isready -h ${pgSocket} -p ${toString pgPort} -q && break
          sleep 1
        done

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

    # ── ensure additional databases (idempotent, every boot) ─────────────────
    # creates databases + roles declared in cfg.db.databases. Runs AFTER init-sql
    # (so the cluster is ready) and on every boot (not sentinel-guarded). Each
    # role's password is sourced from its agenix secret at runtime.
    systemd.services.supabase-db-ensure-dbs = mkIf (cfg.db.databases != { }) {
      description = "supabase db: ensure additional databases + roles";
      after = [
        "supabase-db-init-sql.service"
        "run-agenix.d.mount"
      ];
      requires = [ "supabase-db.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = pgUser;
        RemainAfterExit = true;
      };

      path = [
        supabasePg
        pkgs.coreutils
      ];

      script =
        let
          psqlNoStop = "psql -h ${pgSocket} -p ${toString pgPort} -U postgres";
          dbScript = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (dbName: spec: ''
              # ensure role (idempotent)
              ${psqlNoStop} -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${dbName}') THEN CREATE ROLE \"${dbName}\" WITH LOGIN; END IF; END \$\$;"

              # PG17 requires SET ROLE capability to assign ownership — grant it
              ${psqlNoStop} -c "GRANT \"${dbName}\" TO postgres;"

              # ensure database (idempotent)
              ${psqlNoStop} -tc "SELECT 1 FROM pg_database WHERE datname = '${dbName}'" | grep -q 1 \
                || ${psqlNoStop} -c "CREATE DATABASE \"${dbName}\" OWNER \"${dbName}\";"

              # PG17 revoked public schema CREATE by default — grant it to the owner
              ${psqlNoStop} -d ${dbName} -c "GRANT ALL ON SCHEMA public TO \"${dbName}\";"
              ${psqlNoStop} -d ${dbName} -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"${dbName}\";"

              # set password from agenix secret
              if [ -r "/run/agenix/${spec.passwordSecret}" ]; then
                ${
                  if spec.rawPassword then
                    ''
                      pw=$(cat "/run/agenix/${spec.passwordSecret}" | tr -d '\n')
                    ''
                  else
                    ''
                      pw=$( set -a; . "/run/agenix/${spec.passwordSecret}"; printf '%s' "''$${spec.passwordVar}" )
                    ''
                }
                if [ -n "$pw" ]; then
                  ${psqlNoStop} -c "ALTER ROLE \"${dbName}\" WITH LOGIN PASSWORD '$pw';"
                  echo "// supabase-db-ensure-dbs // ${dbName}: role password set"
                else
                  echo "warning: password empty in /run/agenix/${spec.passwordSecret}" >&2
                fi
              else
                echo "warning: /run/agenix/${spec.passwordSecret} not readable for ${dbName}" >&2
              fi
            '') cfg.db.databases
          );
        in
        ''
          set -euo pipefail

          # wait for PG to be ready (Type=simple means systemd doesn't gate on readiness)
          for i in $(seq 1 30); do
            pg_isready -h ${pgSocket} -p ${toString pgPort} -q && break
            sleep 1
          done

          echo "// supabase-db-ensure-dbs // ensuring ${toString (builtins.length (builtins.attrNames cfg.db.databases))} database(s)"
          ${dbScript}
          echo "// supabase-db-ensure-dbs // done"
        '';
    };

    # ── one-time data migration from old clusters (sentinel-guarded) ─────────
    # For each database with migrate.enable = true: pg_dump from the old cluster,
    # pg_restore into the supabase PG17 cluster. Runs once per database.
    # ConditionPathExists ensures it only runs once (sentinel file in pgDataDir).
    systemd.services."supabase-db-migrate-atticd" =
      mkIf (cfg.db.databases ? atticd && cfg.db.databases.atticd.migrate.enable)
        {
          description = "one-time migration: atticd from old cluster to PG17";
          after = [ "supabase-db-ensure-dbs.service" ];
          requires = [ "supabase-db.service" ];
          wantedBy = [ "multi-user.target" ];
          unitConfig.ConditionPathExists = "!${pgDataDir}/.migrated-atticd";

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };

          path = [
            supabasePg
            pkgs.postgresql_16
            pkgs.coreutils
            pkgs.sudo
          ];

          script =
            let
              m = cfg.db.databases.atticd.migrate;
            in
            ''
              set -euo pipefail
              echo "// supabase-db-migrate-atticd // dumping from port ${toString m.sourcePort}"

              # check if the old cluster is reachable
              if ! pg_isready -h ${m.sourceSocketDir} -p ${toString m.sourcePort} -q; then
                echo "// supabase-db-migrate-atticd // old cluster not running, skipping"
                echo "// start the old PG16 once for migration, or set migrate.enable = false"
                exit 1
              fi

              # dump from old cluster (peer auth)
              sudo -u ${m.sourceUser} pg_dump \
                -h ${m.sourceSocketDir} \
                -p ${toString m.sourcePort} \
                -d atticd \
                -Fc --no-owner --no-acl \
                -f /tmp/migrate-atticd.dump

              echo "// supabase-db-migrate-atticd // restoring into port ${toString pgPort}"

              # restore into supabase cluster
              sudo -u ${pgUser} pg_restore \
                -h ${pgSocket} \
                -p ${toString pgPort} \
                -U postgres \
                -d atticd \
                --no-owner --no-acl \
                --if-exists --clean \
                /tmp/migrate-atticd.dump || true

              rm -f /tmp/migrate-atticd.dump
              touch "${pgDataDir}/.migrated-atticd"
              echo "// supabase-db-migrate-atticd // done"
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
        # auth — GoTrue serves at root, strip /auth/v1 prefix
        "/auth/v1/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.auth.port}/";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Path /auth/v1;
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

        # postgres-meta (studio backend) — passes X-PG-Meta-Db from cookie
        "/pg/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.meta.port}/";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header Host $host;
            proxy_set_header X-PG-Meta-Db $cookie_pg_meta_db;
          '';
        };

        # studio (dashboard) — catch-all (native DatabaseDropdown in fork handles db picker)
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
        RELEASE_TMP = "/var/lib/supabase-realtime/tmp";
        ERL_CRASH_DUMP = "/var/lib/supabase-realtime/tmp/erl_crash.dump";
        # Mix requires HOME at runtime (extra_applications: [:mix])
        HOME = "/var/lib/supabase-realtime";

      };

      # BEAM's disksup shells out to `df` — needs coreutils + util-linux on PATH.
      # Also set in the environment because the release's env.sh may reset PATH.
      path = [
        pkgs.coreutils
        pkgs.util-linux
        pkgs.bash
      ];

      environment.PATH = lib.mkForce (
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.util-linux
          pkgs.bash
          pkgs.gnused
          pkgs.gnugrep
          pkgs.gawk
        ]
      );

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
              mkdir -p /var/lib/supabase-realtime/tmp
              ${supabaseRealtime}/bin/supabase-realtime eval 'Realtime.Release.migrate()'
              ${supabaseRealtime}/bin/supabase-realtime eval 'Realtime.Release.seeds(Realtime.Repo)'
            '';
          in
          "+${migrateScript}";

        ExecStart = "${supabaseRealtime}/bin/supabase-realtime start";
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectHome = true;
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
        FILE_STORAGE_BACKEND_PATH = "/var/lib/supabase-storage";
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
        WorkingDirectory = "${supabaseStorage}/app";
        EnvironmentFile = svcEnv "storage";
        DynamicUser = true;
        StateDirectory = "supabase-storage";
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectHome = true;
        ReadWritePaths = [ "${cfg.dataDir}/storage" ];
        NoNewPrivileges = true;
      };
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  Studio — Next.js app built from sensenet-ai/supabase fork
    # ══════════════════════════════════════════════════════════════════════════════

    systemd.services.supabase-studio = {
      description = "supabase studio (sensenet-ai fork, native build)";
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

    # ── tailnet firewall: expose PG17 port on tailscale0 for fleet replicas ──
    networking.firewall.interfaces.${cfg.db.tailnet.interface} = lib.mkIf cfg.db.tailnet.enable {
      allowedTCPPorts = [ pgPort ];
    };

    # ══════════════════════════════════════════════════════════════════════════════
    #  PITR — pgbackrest continuous WAL archiving to R2
    # ══════════════════════════════════════════════════════════════════════════════

    environment.etc."pgbackrest/pgbackrest-supabase.conf" = lib.mkIf cfg.db.pitr.enable {
      text = ''
        [global]
        repo1-type=s3
        repo1-s3-bucket=${cfg.db.pitr.s3.bucket}
        repo1-s3-endpoint=${cfg.db.pitr.s3.endpoint}
        repo1-s3-region=${cfg.db.pitr.s3.region}
        repo1-s3-uri-style=path
        repo1-retention-full=4
        repo1-bundle=y
        compress-type=zst
        compress-level=6
        process-max=4
        start-fast=y
        lock-path=/run/pgbackrest-supabase
        log-path=/var/log/pgbackrest
        log-level-file=info

        [global:archive-push]
        log-level-file=info

        [${cfg.db.pitr.stanza}]
        pg1-path=${pgDataDir}
        pg1-port=${toString pgPort}
        pg1-socket-path=${pgSocket}
        pg1-user=supabase_admin
      '';
    };

    # one-time stanza-create (idempotent)
    systemd.services.supabase-pgbackrest-stanza-create = lib.mkIf cfg.db.pitr.enable {
      description = "pgbackrest stanza-create for supabase PG17";
      after = [ "supabase-db.service" ];
      requires = [ "supabase-db.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = pgUser;
        RemainAfterExit = true;
        EnvironmentFile = cfg.db.pitr.environmentFile;
      };
      path = [
        pkgs.pgbackrest
        supabasePg
      ];
      script = ''
        pgbackrest --config=/etc/pgbackrest/pgbackrest-supabase.conf \
          --stanza=${cfg.db.pitr.stanza} stanza-create || \
        pgbackrest --config=/etc/pgbackrest/pgbackrest-supabase.conf \
          --stanza=${cfg.db.pitr.stanza} stanza-upgrade || true
        # skip `check` on first run — it fails before the first WAL segment is archived.
        # the first archive-push (triggered by archive_timeout=60) validates the setup.
      '';
    };

    # daily differential base backup
    systemd.services.supabase-pgbackrest-backup-diff = lib.mkIf cfg.db.pitr.enable {
      description = "pgbackrest differential backup (supabase PG17)";
      after = [ "supabase-db.service" ];
      requires = [ "supabase-db.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = pgUser;
        EnvironmentFile = cfg.db.pitr.environmentFile;
        ExecStart = "${pkgs.pgbackrest}/bin/pgbackrest --config=/etc/pgbackrest/pgbackrest-supabase.conf --stanza=${cfg.db.pitr.stanza} --type=diff backup";
      };
      path = [ supabasePg ];
    };

    # weekly full base backup
    systemd.services.supabase-pgbackrest-backup-full = lib.mkIf cfg.db.pitr.enable {
      description = "pgbackrest full backup (supabase PG17)";
      after = [ "supabase-db.service" ];
      requires = [ "supabase-db.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = pgUser;
        EnvironmentFile = cfg.db.pitr.environmentFile;
        ExecStart = "${pkgs.pgbackrest}/bin/pgbackrest --config=/etc/pgbackrest/pgbackrest-supabase.conf --stanza=${cfg.db.pitr.stanza} --type=full backup";
      };
      path = [ supabasePg ];
    };

    systemd.timers.supabase-pgbackrest-backup-diff = lib.mkIf cfg.db.pitr.enable {
      description = "schedule pgbackrest differential backups (supabase PG17)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
    };

    systemd.timers.supabase-pgbackrest-backup-full = lib.mkIf cfg.db.pitr.enable {
      description = "schedule pgbackrest full backups (supabase PG17)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun *-*-* 02:00:00";
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
    };
  };
}
