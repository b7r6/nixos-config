# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                          // hyper-modern-nixos // attic-node
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# "Be an attic cache node." A profile selector over the orthogonal attic axes
# (mode × database × storage), so any host switches cleanly REGARDLESS of fleet
# state. Each host is just:
#
#     age.secrets.atticd-rs256.file     = …/atticd-rs256.age;
#     age.secrets.attic-push-token.file = …/attic-push-token.age;
#     hyper-modern-nixos.attic-node = { enable = true; profile = "…"; };
#
# Profiles:
#
#   standalone  — monolithic atticd, SELF-CONTAINED. Local sqlite (default) or a
#                 local postgres, local storage (default) or R2. Depends on NO
#                 other host, so it activates cleanly anywhere, today. This is
#                 the profile to run before watchtower's shared postgres exists,
#                 or for any island cache.
#
#   replica     — stateless api-server. Shares the fleet postgres (watchtower)
#                 + the R2 chunk store + RS256 secret. Requires that shared
#                 postgres to be reachable and ALREADY MIGRATED (a monolithic
#                 node runs migrations; a bare api-server does not). Use once the
#                 fleet backend is up.
#
#   monolithic-shared — monolithic atticd ON the shared backend (watchtower's
#                 role): runs migrations + serves + the single GC, against the
#                 shared postgres + R2. Exactly one node in the fleet uses this.
#
# Every profile points nix's substituters at this host's OWN localhost:8080
# (first in line, no serialization) and watch-store auto-pushes. The choice of
# profile only changes mode/database/storage — the cache identity (name, public
# key, push token) is constant, so a host can be flipped standalone↔replica by
# changing one enum with no other churn.
{
  config,
  lib,
  flake,
  ...
}:
let
  cfg = config.hyper-modern-nixos.attic-node;

  # Single source of truth for the tailnet MagicDNS suffix — never hardcode it.
  tailnetDomain = config.hyper-modern-nixos.network.tailnet.domain;

  # This module SELF-WIRES the agenix secrets it needs (the .age files live in
  # the repo; flake.self is the repo root). So a host only sets
  # `attic-node = { enable = true; profile = "…"; }` — no parallel age.secrets
  # gating. The decrypted runtime paths stay /run/agenix/<name>.
  machineSecrets = flake.self + "/secrets/agenix/machines";

  isStandalone = cfg.profile == "standalone";
  usesSharedPg = cfg.profile == "replica" || cfg.profile == "monolithic-shared";

  mode = if cfg.profile == "replica" then "api-server" else "monolithic";

  # storage: standalone uses local fs unless r2.enable; shared profiles always
  # use R2 (the fleet chunk store).
  useR2 = cfg.r2.enable || usesSharedPg;
in
{
  options.hyper-modern-nixos.attic-node = {
    enable = lib.mkEnableOption "attic cache node (profile-selected)";

    profile = lib.mkOption {
      type = lib.types.enum [
        "standalone"
        "replica"
        "monolithic-shared"
      ];
      default = "standalone";
      description = ''
        standalone        : monolithic, self-contained (local sqlite/pg + local
                            storage unless r2.enable). No fleet dependency.
        replica           : api-server against the shared fleet postgres + R2.
                            Requires the shared pg up + already migrated.
        monolithic-shared : monolithic against the shared pg + R2 (watchtower's
                            role; runs migrations + the single GC). Exactly one.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/atticd-rs256";
      description = ''
        Decrypted env file. Always carries ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64
        (identical fleet-wide). For R2-backed profiles it also carries
        AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY. For shared-postgres profiles it
        also carries PGPASSWORD (sqlx reads it). The host declares
        age.secrets.atticd-rs256 pointing at the agenix file.
      '';
    };

    pushTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/run/agenix/attic-push-token";
      description = ''
        Decrypted push JWT for watch-store auto-push. null disables auto-push
        (pull-only) — useful for a freshly-bootstrapped standalone node before a
        token exists.
      '';
    };

    # ── database ────────────────────────────────────────────────────────────
    sharedDatabaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgresql://atticd@watchtower.${tailnetDomain}/atticd";
      defaultText = "postgresql://atticd@watchtower.\${network.tailnet.domain}/atticd";
      description = ''
        Passwordless shared-postgres connection string for replica /
        monolithic-shared (PGPASSWORD via env file). Ignored by standalone. The
        tailnet suffix is derived from network.tailnet.domain (single source).
      '';
    };

    useSupabaseDb = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use the supabase-native PG17 cluster instead of the legacy PG16.
        When true, monolithic-shared skips enabling the old
        hyper-modern-nixos.databases.postgres and connects to the supabase
        cluster (port from hyper-modern-nixos.supabase-native.db.port).
        The atticd database + role must be declared in
        hyper-modern-nixos.supabase-native.db.databases.atticd.
        The old PG16 cluster is left untouched (no data lost).
      '';
    };

    standalonePostgres = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        standalone only: use a LOCAL postgres (this module enables it) instead of
        the default local sqlite. Handy to rehearse the postgres path on one box.
      '';
    };

    # ── storage ───────────────────────────────────────────────────────────────
    r2 = {
      enable = lib.mkEnableOption "back storage with R2 (forced on for shared profiles)";

      bucket = lib.mkOption {
        type = lib.types.str;
        default = "straylight-attic-cache";
        description = "R2 chunk-store bucket (owned fleet-wide by atticd).";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "https://6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com";
        description = "R2 S3 endpoint.";
      };
    };

    publicKey = lib.mkOption {
      type = lib.types.str;
      default = "hypermodern:x+kBunu5nD1KOhzCIawyZeq8w0LV0GC6A7suIRoHTm8=";
      description = "The `hypermodern` cache's binary-cache public key.";
    };

    cacheName = lib.mkOption {
      type = lib.types.str;
      default = "hypermodern";
      description = "The cache name (URL path segment + DB cache row).";
    };

    keypairSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "attic-cache-keypair";
      description = ''
        monolithic-shared only: agenix secret NAME holding the cache's NixKeypair
        string. Restored into the postgres `cache` table on activation so the
        signing identity is STABLE across a postgres wipe (attic only stores it in
        the DB and can't import it). null disables restore (use the DB-generated
        key, which changes on a wipe).
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        # Sanity: shared profiles must be able to authenticate; standalone must
        # not accidentally point at a remote DB.
        assertions = [
          {
            assertion = !(isStandalone && usesSharedPg);
            message = "attic-node: contradictory profile derivation (internal).";
          }
        ];

        # Self-wire the agenix secrets this node needs. Every profile needs the
        # atticd env (RS256 + R2 [+ PGPASSWORD for shared]) and a push token for
        # watch-store. The host imports the agenix nixos module; this sets the
        # .age files so the host doesn't gate them in lockstep.
        age.secrets = {
          atticd-rs256.file = machineSecrets + "/atticd-rs256.age";
          attic-push-token.file = machineSecrets + "/attic-push-token.age";
        };

        hyper-modern-nixos.attic = {
          enable = true;
          inherit mode;
          inherit (cfg) environmentFile;
          listen = "[::]:8080";
          trustedInterfaces = [ "tailscale0" ];

          # database:
          #   monolithic-shared + useSupabaseDb -> supabase PG17 on its port
          #   monolithic-shared (legacy)        -> old PG16 on localhost:5432
          #   replica                           -> remote shared URL over tailnet
          #   standalone                        -> local postgres if asked, else sqlite
          databaseUrl =
            if cfg.profile == "monolithic-shared" && cfg.useSupabaseDb then
              "postgresql://atticd@localhost:${toString config.hyper-modern-nixos.supabase-native.db.port}/atticd"
            else if cfg.profile == "monolithic-shared" then
              "postgresql://atticd@localhost/atticd"
            else if cfg.profile == "replica" then
              cfg.sharedDatabaseUrl
            else if cfg.standalonePostgres then
              "postgresql://atticd@localhost/atticd"
            else
              null;

          storage =
            if useR2 then
              {
                type = "s3";
                region = "auto";
                inherit (cfg.r2) bucket endpoint;
              }
            else
              { type = "local"; };

          clientCache = {
            enable = true;
            name = "hypermodern";
            endpoint = "http://localhost:8080";
            inherit (cfg) publicKey pushTokenFile;
          };
        };
      }

      # Stand up the LOCAL shared postgres on the node that hosts it:
      #   - monolithic-shared (watchtower): always (it IS the fleet postgres),
      #     tailnet-reachable so replicas can connect.
      #   - standalone + standalonePostgres: a local-only rehearsal postgres.
      # When useSupabaseDb is true, this still runs (so the migration oneshot can
      # dump from it) but atticd no longer connects to it. After the migration
      # sentinel is created, disable migrate.enable and then set this to false on
      # the next rebuild to fully decommission PG16.
      (lib.mkIf (cfg.profile == "monolithic-shared") {
        hyper-modern-nixos.databases.postgres = {
          enable = true;
          tailnet.enable = !cfg.useSupabaseDb; # no tailnet exposure needed if just for migration
          ensureDatabases = [ "atticd" ];
          ensureUsers = [
            {
              name = "atticd";
              ensureDBOwnership = true;
            }
          ];
          # only set role password on the OLD cluster when atticd actually connects
          # to it. When useSupabaseDb, the supabase-native module handles the password.
          rolePasswords = lib.mkIf (!cfg.useSupabaseDb) {
            atticd = {
              secret = "atticd-rs256";
              var = "PGPASSWORD";
            };
          };
        };

        # Persist the cache signing keypair: agenix holds it (postgres-readable),
        # and a oneshot restores it into the `cache` row so the signing identity
        # survives a postgres wipe. Runs after the role-password service (so auth
        # works) and only UPDATEs an EXISTING cache row (the row is created at
        # bootstrap by `attic cache create`; this keeps its key stable thereafter).
        # SKIPPED when useSupabaseDb — the supabase block below handles it.
        age.secrets = lib.mkIf (cfg.keypairSecret != null && !cfg.useSupabaseDb) {
          ${cfg.keypairSecret} = {
            file = machineSecrets + "/${cfg.keypairSecret}.age";
            group = "postgres";
            mode = "0440";
          };
        };

        systemd.services.attic-cache-keypair-restore =
          lib.mkIf (cfg.keypairSecret != null && !cfg.useSupabaseDb)
            {
              description = "restore the attic cache signing keypair into postgres";
              after = [ "postgresql-role-passwords.service" ];
              requires = [ "postgresql.service" ];
              wantedBy = [ "multi-user.target" ];
              before = [ "atticd.service" ];
              serviceConfig = {
                Type = "oneshot";
                User = "postgres";
                RemainAfterExit = true;
              };
              script =
                let
                  psql = "${config.services.postgresql.package}/bin/psql -d atticd -v ON_ERROR_STOP=1";
                  secretPath = "/run/agenix/${cfg.keypairSecret}";
                in
                ''
                  if [ ! -r "${secretPath}" ]; then
                    echo "warning: keypair secret ${secretPath} not readable; skipping" >&2
                    exit 0
                  fi
                  kp=$(cat "${secretPath}")
                  # Only update if the cache row already exists (created at bootstrap).
                  # Idempotent: sets keypair to the agenix-held value every activation.
                  ${psql} -c "UPDATE cache SET keypair = '$kp' WHERE name = '${cfg.cacheName}';" \
                    || echo "warning: failed to restore cache keypair (cache '${cfg.cacheName}' may not exist yet)" >&2
                '';
            };
      })

      # ── monolithic-shared + useSupabaseDb: order atticd after the supabase DB ──
      # The old PG16 is untouched; atticd connects to the supabase cluster instead.
      # The keypair restore targets the supabase cluster's psql.
      (lib.mkIf (cfg.profile == "monolithic-shared" && cfg.useSupabaseDb) {
        assertions = [
          {
            assertion = config.hyper-modern-nixos.supabase-native.enable;
            message = ''
              attic-node.useSupabaseDb requires hyper-modern-nixos.supabase-native.enable.
              The supabase-native module provides the PG17 cluster.
            '';
          }
        ];

        # order atticd after the supabase DB ensures the database + role exist
        systemd.services.atticd = {
          after = [ "supabase-db-ensure-dbs.service" ];
          wants = [ "supabase-db-ensure-dbs.service" ];
        };

        # keypair restore against the supabase cluster
        age.secrets = lib.mkIf (cfg.keypairSecret != null) {
          ${cfg.keypairSecret} = {
            file = machineSecrets + "/${cfg.keypairSecret}.age";
            group = config.users.users."supabase-postgres".group;
            mode = "0440";
          };
        };

        systemd.services.attic-cache-keypair-restore = lib.mkIf (cfg.keypairSecret != null) {
          description = "restore the attic cache signing keypair into supabase postgres";
          after = [ "supabase-db-ensure-dbs.service" ];
          requires = [ "supabase-db.service" ];
          wantedBy = [ "multi-user.target" ];
          before = [ "atticd.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "supabase-postgres";
            RemainAfterExit = true;
          };
          script =
            let
              supabasePgPort = toString config.hyper-modern-nixos.supabase-native.db.port;
              supabasePgSocket = config.hyper-modern-nixos.supabase-native.db.socketDir;
              psql = "psql -h ${supabasePgSocket} -p ${supabasePgPort} -U postgres -d atticd -v ON_ERROR_STOP=1";
              secretPath = "/run/agenix/${cfg.keypairSecret}";
            in
            ''
              if [ ! -r "${secretPath}" ]; then
                echo "warning: keypair secret ${secretPath} not readable; skipping" >&2
                exit 0
              fi
              kp=$(cat "${secretPath}")
              ${psql} -c "UPDATE cache SET keypair = '$kp' WHERE name = '${cfg.cacheName}';" \
                || echo "warning: failed to restore cache keypair (cache '${cfg.cacheName}' may not exist yet)" >&2
            '';
        };
      })

      (lib.mkIf (isStandalone && cfg.standalonePostgres) {
        hyper-modern-nixos.databases.postgres = {
          enable = true;
          ensureDatabases = [ "atticd" ];
          ensureUsers = [
            {
              name = "atticd";
              ensureDBOwnership = true;
            }
          ];
        };
      })
    ]
  );
}
