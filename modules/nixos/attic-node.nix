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
{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.attic-node;

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
      default = "postgresql://atticd@watchtower.osiris-walleye.ts.net/atticd";
      description = ''
        Passwordless shared-postgres connection string for replica /
        monolithic-shared (PGPASSWORD via env file). Ignored by standalone.
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
      default = "hypermodern:IxmiCAZWTeYmnOafmhz39qrn0wXj+aNvBy9dczJTcAs=";
      description = "The `hypermodern` cache's binary-cache public key.";
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

        hyper-modern-nixos.attic = {
          enable = true;
          inherit mode;
          inherit (cfg) environmentFile;
          listen = "[::]:8080";
          trustedInterfaces = [ "tailscale0" ];

          # database:
          #   monolithic-shared (watchtower) IS the postgres host -> loopback
          #   replica            -> the remote shared URL over the tailnet
          #   standalone         -> local postgres if asked, else sqlite default
          databaseUrl =
            if cfg.profile == "monolithic-shared" then
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
      (lib.mkIf (cfg.profile == "monolithic-shared") {
        hyper-modern-nixos.databases.postgres = {
          enable = true;
          tailnet.enable = true;
          ensureDatabases = [ "atticd" ];
          ensureUsers = [
            {
              name = "atticd";
              ensureDBOwnership = true;
            }
          ];
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
