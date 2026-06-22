# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // supabase
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#   "Multiple services require specific configuration within the Postgres
#    database. Refer to the documentation describing the default roles."
#
# Self-hosted Supabase as a NixOS module, OFF BY DEFAULT. Live (when enabled) on
# watchtower. See docs/src/services/supabase.md for the full design.
#
# ── Why containers (and why that's still a "native" module) ─────────────────
# There is NO upstream NixOS module and the stack does not exist in nixpkgs
# (only postgrest + imgproxy do; Studio / postgres-meta / Kong / Realtime /
# Storage / the supabase `auth` fork do not). More fundamentally, the `db` MUST
# be the supabase/postgres image: its ~30 extensions + the role/schema init SQL
# are not reproducible from pkgs.postgresql. So this drives the upstream,
# version-tested OCI images via `virtualisation.oci-containers` — the hardened
# artifact — while everything AROUND them is real NixOS: declarative units, a
# pinned image set, agenix-fed secrets (never the store), firewall posture, and
# state classification. "Containers where containers belong", tracked by Nix.
#
# ── Config-file provenance (the version-coupling trap, handled) ─────────────
# db/kong/supavisor need config files that ship in upstream's docker/volumes/
# tree, NOT in the images: 7 db init SQLs, the 440-line kong.yml, pooler.exs.
# Hand-transcribing them rots on the next image bump. Instead they come from the
# `supabase` flake input PINNED IN LOCKSTEP with the image tags below — one
# content-addressed checkout, version-coherent by construction.
#
# ── Phase one: self-contained, atticd/Forgejo untouched ─────────────────────
# Supabase runs its OWN postgres cluster (the db container, /var/lib/supabase/db)
# and connects to NOTHING in the existing fleet. No change to watchtower's
# system-of-record cluster (atticd's DB, the cache signing keypair, the
# pgBackRest `main` stanza). Browsing atticd/Forgejo in Studio + CDC to
# ClickHouse are deferred to post-rewrite (see the design doc).
{
  config,
  lib,
  pkgs,
  flake ? null,
  ...
}:
let
  cfg = config.hyper-modern-nixos.supabase;

  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  # The pinned upstream source tree (flake = false). docker/volumes/ holds the
  # version-coupled config files. null-guarded so the module still evaluates in
  # contexts without the flake specialArg (e.g. a bare import in a test).
  src = if flake != null then flake.inputs.supabase else null;
  vol = "${src}/docker/volumes";

  # Internal docker network: upstream services resolve each other by these exact
  # names (STUDIO_PG_META_URL=http://meta:8080, PGRST host `rest`, db host `db`…).
  net = "supabase";

  pgHost = "db";
  pgPort = "5432";
  pgDb = "postgres";

  # ── Per-service env files (the secret split) ───────────────────────────────
  # The agenix bundle (cfg.environmentFile) carries ONLY the raw secrets
  # (POSTGRES_PASSWORD, JWT_SECRET, ANON_KEY, SERVICE_ROLE_KEY, SECRET_KEY_BASE,
  # VAULT_ENC_KEY, PG_META_CRYPTO_KEY, DASHBOARD_*). It is NOT handed to the
  # containers directly, because several services need DIFFERENT vars built from
  # the SAME password — notably both `auth` and `storage` read a var literally
  # named DATABASE_URL but with a DIFFERENT role in the URL, so one shared file
  # can't satisfy both.
  #
  # Instead, the supabase-env-split oneshot (below) sources the bundle at
  # activation and writes one env file PER SERVICE into runtimeEnvDir, composing
  # the password-embedded DB URLs under each image's EXACT var name. The password
  # never enters the nix store (it's only ever in the agenix-decrypted bundle and
  # the 0600 root-owned per-service files under /run). Each container's
  # environmentFiles points at its own file.
  runtimeEnvDir = "/run/supabase/env";
  svcEnv = name: "${runtimeEnvDir}/${name}";

  # Shorthand for the common per-container bits: the private network, this
  # service's own runtime env file, AND a network ALIAS matching the short
  # upstream name. oci-containers names the container `supabase-<name>`, but the
  # services address each other by the short name (db, meta, rest, kong, …) — the
  # same names baked into kong.yml / STUDIO_PG_META_URL / the composed DB URLs.
  # Docker's embedded DNS only resolves a user-network member by its container
  # name unless an alias is set, so without this every cross-service lookup
  # (e.g. gotrue → `host=db`) fails with NXDOMAIN. compose gets this for free via
  # the service name; here we set it explicitly.
  common = name: {
    extraOptions = [
      "--network=${net}"
      "--network-alias=${name}"
    ];
    environmentFiles = [ (svcEnv name) ];
  };
in
{
  options.hyper-modern-nixos.supabase = {
    enable = mkEnableOption "self-hosted Supabase (full stack, off by default)";

    environmentFile = mkOption {
      type = types.str;
      default = "/run/agenix/supabase-env";
      description = ''
        Decrypted env file carrying the whole secret bundle (JWT_SECRET,
        ANON_KEY, SERVICE_ROLE_KEY, POSTGRES_PASSWORD, SECRET_KEY_BASE,
        VAULT_ENC_KEY, PG_META_CRYPTO_KEY, DASHBOARD_*). Generate with
        `nix run .#gen-supabase-secrets`. The module self-wires the agenix
        secret (supabase-env) when `selfWireSecret` is true.
      '';
    };

    selfWireSecret = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Self-wire age.secrets.supabase-env from the in-repo .age file. Disable to
        manage the agenix secret yourself (e.g. a different name/path).
      '';
    };

    publicUrl = mkOption {
      type = types.str;
      default = "http://localhost:8000";
      example = "https://studio.sju1.s4.gl";
      description = ''
        Externally-reachable base URL (through nginx → Kong). Drives
        SUPABASE_PUBLIC_URL / API_EXTERNAL_URL / SITE_URL. Set this to the nginx
        vhost once the reverse proxy fronts it.
      '';
    };

    kong = {
      httpPort = mkOption {
        type = types.port;
        default = 8000;
        description = "Host port Kong's HTTP gateway binds (loopback; nginx fronts it).";
      };
      httpsPort = mkOption {
        type = types.port;
        default = 8443;
        description = "Host port Kong's HTTPS gateway binds (loopback).";
      };
      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Bind address for Kong's published ports. Loopback by default (front with nginx).";
      };
    };

    studioPort = mkOption {
      type = types.port;
      default = 3000;
      description = "Internal Studio port (not published; reached via Kong).";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/supabase";
      description = ''
        Parent of the cluster (db/) and Storage (storage/) state. Classified
        `authoritative` (persisted across an impermanence reboot AND backed up to
        R2). Distinct from atticd's cluster.
      '';
    };

    # ── Pinned image set ────────────────────────────────────────────────────
    # Defaults are the exact tags from the locked upstream docker-compose. Bump
    # these IN LOCKSTEP with the `supabase` flake input (the config files must
    # match the images). See docs for the bump procedure.
    images = {
      studio = mkOption {
        type = types.str;
        default = "supabase/studio:2026.06.03-sha-0bca601";
        description = "Studio (dashboard) image.";
      };
      kong = mkOption {
        type = types.str;
        default = "kong/kong:3.9.1";
        description = "Kong API gateway image.";
      };
      auth = mkOption {
        type = types.str;
        default = "supabase/gotrue:v2.189.0";
        description = "GoTrue (supabase/auth) image.";
      };
      rest = mkOption {
        type = types.str;
        default = "postgrest/postgrest:v14.12";
        description = "PostgREST image.";
      };
      realtime = mkOption {
        type = types.str;
        default = "supabase/realtime:v2.102.3";
        description = "Realtime image.";
      };
      storage = mkOption {
        type = types.str;
        default = "supabase/storage-api:v1.60.4";
        description = "Storage API image.";
      };
      imgproxy = mkOption {
        type = types.str;
        default = "darthsim/imgproxy:v3.30.1";
        description = "imgproxy image.";
      };
      meta = mkOption {
        type = types.str;
        default = "supabase/postgres-meta:v0.96.6";
        description = "postgres-meta image.";
      };
      db = mkOption {
        type = types.str;
        default = "supabase/postgres:17.6.1.136";
        description = "Patched Postgres image (the cluster).";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hyper-modern-nixos.docker.enable;
        message = "hyper-modern-nixos.supabase needs hyper-modern-nixos.docker.enable (the oci-containers backend).";
      }
      {
        assertion = src != null;
        message = ''
          hyper-modern-nixos.supabase needs the `flake` specialArg (for the pinned
          `supabase` input that provides the db/kong/pooler config files). It is
          provided by the fleet wiring; bare imports must pass it.
        '';
      }
    ];

    # Self-wire the secret bundle. Root-owned (containers read it as root via
    # EnvironmentFile, before any DynamicUser); never the store.
    age.secrets = mkIf cfg.selfWireSecret {
      supabase-env.file = flake.self + "/secrets/agenix/machines/supabase-env.age";
    };

    # Cluster + Storage state → authoritative (persisted + restic'd). Distinct
    # from atticd. The db container owns uid/gid inside; the dirs just need to
    # exist with sane perms for the bind mounts.
    hyper-modern-nixos.state.dirs = {
      supabase-db = {
        path = "${cfg.dataDir}/db";
        class = "authoritative";
      };
      supabase-storage = {
        path = "${cfg.dataDir}/storage";
        class = "authoritative";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
      "d ${cfg.dataDir}/db 0750 root root - -"
      "d ${cfg.dataDir}/storage 0750 root root - -"
    ];

    # The oci-containers backend is docker (fleet default). Create the shared
    # network once, before any container starts.
    virtualisation.oci-containers.backend = "docker";

    systemd.services = lib.mkMerge [
      {
        docker-network-supabase = {
          description = "create the supabase docker network";
          after = [ "docker.service" ];
          requires = [ "docker.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ${pkgs.docker}/bin/docker network inspect ${net} >/dev/null 2>&1 \
              || ${pkgs.docker}/bin/docker network create ${net}
          '';
        };

        # ── supabase-env-split: agenix bundle → per-service env files ───────────────
        # Sources the decrypted secret bundle and writes one 0600 root-owned env file
        # per service into runtimeEnvDir, composing the password-embedded DB URLs
        # under each image's EXACT var name. This is what lets `auth` and `storage`
        # each get their own DATABASE_URL (different roles) from one shared password,
        # and keeps the password out of the nix store. Every container unit is ordered
        # after this (and re-run if the bundle changes).
        supabase-env-split = {
          description = "compose supabase per-service env files from the agenix bundle";
          after = [ "run-agenix.d.mount" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          # Re-run when the decrypted bundle changes (rotate-secret → new content).
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

            # url <role> → postgres://<role>:<pw>@db:5432/postgres. NOTE: written with
            # printf (not indented heredocs) so no leading whitespace ever leaks into
            # the env files — systemd EnvironmentFile would treat " KEY=v" as invalid.
            url() { printf 'postgres://%s:%s@${pgHost}:${pgPort}/${pgDb}' "$1" "$POSTGRES_PASSWORD"; }

            # db: cluster init reads POSTGRES_PASSWORD (+ PGPASSWORD for psql).
            printf '%s\n' \
              "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
              "PGPASSWORD=$POSTGRES_PASSWORD" > "$d/db"

            # meta: postgres-meta connects as the postgres superuser.
            printf '%s\n' \
              "PG_META_DB_PASSWORD=$POSTGRES_PASSWORD" \
              "CRYPTO_KEY=$PG_META_CRYPTO_KEY" > "$d/meta"

            # auth (gotrue): DATABASE_URL (envconfig namespace `gotrue`) as the auth
            # admin role + the HS256 JWT secret. Both names set for version safety.
            printf '%s\n' \
              "GOTRUE_DATABASE_URL=$(url supabase_auth_admin)" \
              "DATABASE_URL=$(url supabase_auth_admin)" \
              "GOTRUE_JWT_SECRET=$JWT_SECRET" > "$d/auth"

            # rest (postgrest): the `authenticator` role + JWT verification secret.
            printf '%s\n' \
              "PGRST_DB_URI=$(url authenticator)" \
              "PGRST_JWT_SECRET=$JWT_SECRET" \
              "PGRST_APP_SETTINGS_JWT_SECRET=$JWT_SECRET" > "$d/rest"

            # realtime: discrete DB_* parts + the Elixir secret bases.
            printf '%s\n' \
              "DB_PASSWORD=$POSTGRES_PASSWORD" \
              "API_JWT_SECRET=$JWT_SECRET" \
              "METRICS_JWT_SECRET=$JWT_SECRET" \
              "SECRET_KEY_BASE=$SECRET_KEY_BASE" > "$d/realtime"

            # storage: its own DATABASE_URL as the storage admin role + API keys.
            printf '%s\n' \
              "DATABASE_URL=$(url supabase_storage_admin)" \
              "ANON_KEY=$ANON_KEY" \
              "SERVICE_KEY=$SERVICE_ROLE_KEY" \
              "AUTH_JWT_SECRET=$JWT_SECRET" > "$d/storage"

            # imgproxy: no secrets (local fs transforms).
            : > "$d/imgproxy"

            # studio: dashboard; talks to meta + kong, needs the API keys + pw.
            printf '%s\n' \
              "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
              "PG_META_CRYPTO_KEY=$PG_META_CRYPTO_KEY" \
              "SUPABASE_ANON_KEY=$ANON_KEY" \
              "SUPABASE_SERVICE_KEY=$SERVICE_ROLE_KEY" \
              "AUTH_JWT_SECRET=$JWT_SECRET" > "$d/studio"

            # kong: the gateway injects the anon/service keys + dashboard basic-auth.
            printf '%s\n' \
              "SUPABASE_ANON_KEY=$ANON_KEY" \
              "SUPABASE_SERVICE_KEY=$SERVICE_ROLE_KEY" \
              "DASHBOARD_USERNAME=$DASHBOARD_USERNAME" \
              "DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD" > "$d/kong"

            chmod 0600 "$d"/*
          '';
        };
      }

      # Order every supabase container after the network + the env split, and
      # bind them so a missing/empty bundle fails fast instead of a
      # credential-less boot. oci-containers generates `docker-<name>.service`;
      # we extend those units here.
      (lib.genAttrs
        [
          "docker-supabase-db"
          "docker-supabase-meta"
          "docker-supabase-auth"
          "docker-supabase-rest"
          "docker-supabase-realtime"
          "docker-supabase-imgproxy"
          "docker-supabase-storage"
          "docker-supabase-studio"
          "docker-supabase-kong"
        ]
        (_: {
          after = [
            "docker-network-supabase.service"
            "supabase-env-split.service"
          ];
          requires = [
            "docker-network-supabase.service"
            "supabase-env-split.service"
          ];
        })
      )

      # Startup-race tolerance. oci-containers `dependsOn` is start-ORDER, not a
      # health WAIT — the db-client services boot before the cluster finishes its
      # (first-boot, ~minute-long) init and `host=db` migrations. Upstream relies
      # on compose healthchecks; we instead let these services keep retrying
      # patiently rather than tripping the default 5-in-10s start limit and giving
      # up (which previously needed a manual `systemctl restart`). A cold boot now
      # converges on its own. db/meta/imgproxy have no such dependency.
      (lib.genAttrs
        [
          "docker-supabase-auth"
          "docker-supabase-rest"
          "docker-supabase-realtime"
          "docker-supabase-storage"
          "docker-supabase-studio"
          "docker-supabase-kong"
        ]
        (_: {
          startLimitIntervalSec = 0; # disable the burst limit → retry forever
          serviceConfig.RestartSec = "5s";
        })
      )
    ];

    virtualisation.oci-containers.containers = {
      # ── db: the cluster (must be the patched image) ─────────────────────────
      # Init SQL + pgdata come from the pinned upstream tree / the state dir. The
      # PGPORT/PGPASSWORD/etc. come from the env file.
      supabase-db = (common "db") // {
        image = cfg.images.db;
        cmd = [
          "postgres"
          "-c"
          "config_file=/etc/postgresql/postgresql.conf"
          "-c"
          "log_min_messages=fatal"
        ];
        environment = {
          POSTGRES_HOST = "/var/run/postgresql";
          PGPORT = pgPort;
          POSTGRES_PORT = pgPort;
          PGDATABASE = pgDb;
          POSTGRES_DB = pgDb;
        };
        volumes = [
          "${vol}/db/realtime.sql:/docker-entrypoint-initdb.d/migrations/99-realtime.sql:ro"
          "${vol}/db/webhooks.sql:/docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql:ro"
          "${vol}/db/roles.sql:/docker-entrypoint-initdb.d/init-scripts/99-roles.sql:ro"
          "${vol}/db/jwt.sql:/docker-entrypoint-initdb.d/init-scripts/99-jwt.sql:ro"
          "${vol}/db/_supabase.sql:/docker-entrypoint-initdb.d/migrations/97-_supabase.sql:ro"
          "${vol}/db/logs.sql:/docker-entrypoint-initdb.d/migrations/99-logs.sql:ro"
          "${vol}/db/pooler.sql:/docker-entrypoint-initdb.d/migrations/99-pooler.sql:ro"
          "${cfg.dataDir}/db:/var/lib/postgresql/data"
        ];
      };

      # ── meta: postgres-meta (Studio's backend) ──────────────────────────────
      supabase-meta = (common "meta") // {
        image = cfg.images.meta;
        dependsOn = [ "supabase-db" ];
        environment = {
          PG_META_PORT = "8080";
          PG_META_DB_HOST = pgHost;
          PG_META_DB_PORT = pgPort;
          PG_META_DB_NAME = pgDb;
          PG_META_DB_USER = "postgres";
          # PG_META_DB_PASSWORD + CRYPTO_KEY come from the env file.
        };
      };

      # ── auth: GoTrue ────────────────────────────────────────────────────────
      supabase-auth = (common "auth") // {
        image = cfg.images.auth;
        dependsOn = [ "supabase-db" ];
        environment = {
          GOTRUE_API_HOST = "0.0.0.0";
          GOTRUE_API_PORT = "9999";
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
          # GOTRUE_DB_DATABASE_URL + GOTRUE_JWT_SECRET come from the env file.
        };
      };

      # ── rest: PostgREST ─────────────────────────────────────────────────────
      supabase-rest = (common "rest") // {
        image = cfg.images.rest;
        dependsOn = [ "supabase-db" ];
        cmd = [ "postgrest" ];
        environment = {
          PGRST_DB_SCHEMAS = "public,storage,graphql_public";
          PGRST_DB_ANON_ROLE = "anon";
          PGRST_DB_USE_LEGACY_GUCS = "false";
          PGRST_ADMIN_SERVER_PORT = "3001";
          # PGRST_DB_URI + PGRST_JWT_SECRET come from the env file.
        };
      };

      # ── realtime ────────────────────────────────────────────────────────────
      supabase-realtime = (common "realtime") // {
        image = cfg.images.realtime;
        dependsOn = [ "supabase-db" ];
        environment = {
          PORT = "4000";
          DB_HOST = pgHost;
          DB_PORT = pgPort;
          DB_USER = "supabase_admin";
          DB_NAME = pgDb;
          DB_AFTER_CONNECT_QUERY = "SET search_path TO _realtime";
          DB_ENC_KEY = "supabaserealtime";
          ERL_AFLAGS = "-proto_dist inet_tcp";
          DNS_NODES = "''";
          RLIMIT_NOFILE = "10000";
          APP_NAME = "realtime";
          SEED_SELF_HOST = "true";
          RUN_JANITOR = "true";
          # DB_PASSWORD / API_JWT_SECRET / SECRET_KEY_BASE / METRICS_JWT_SECRET
          # come from the env file.
        };
      };

      # ── imgproxy (Storage image transforms) ─────────────────────────────────
      supabase-imgproxy = (common "imgproxy") // {
        image = cfg.images.imgproxy;
        environment = {
          IMGPROXY_BIND = ":5001";
          IMGPROXY_LOCAL_FILESYSTEM_ROOT = "/";
          IMGPROXY_USE_ETAG = "true";
          IMGPROXY_AUTO_WEBP = "true";
        };
        volumes = [ "${cfg.dataDir}/storage:/var/lib/storage" ];
      };

      # ── storage ─────────────────────────────────────────────────────────────
      supabase-storage = (common "storage") // {
        image = cfg.images.storage;
        dependsOn = [
          "supabase-db"
          "supabase-rest"
          "supabase-imgproxy"
        ];
        environment = {
          POSTGREST_URL = "http://rest:3000";
          STORAGE_PUBLIC_URL = cfg.publicUrl;
          REQUEST_ALLOW_X_FORWARDED_PATH = "true";
          FILE_SIZE_LIMIT = "52428800";
          STORAGE_BACKEND = "file";
          FILE_STORAGE_BACKEND_PATH = "/var/lib/storage";
          ENABLE_IMAGE_TRANSFORMATION = "true";
          IMGPROXY_URL = "http://imgproxy:5001";
          TENANT_ID = "stub";
          REGION = "stub";
          GLOBAL_S3_BUCKET = "stub";
          # ANON_KEY / SERVICE_KEY / AUTH_JWT_SECRET / DATABASE_URL come from the
          # env file (DATABASE_URL is composed by the image from POSTGRES_*).
        };
        volumes = [ "${cfg.dataDir}/storage:/var/lib/storage" ];
      };

      # ── studio (dashboard) ──────────────────────────────────────────────────
      supabase-studio = (common "studio") // {
        image = cfg.images.studio;
        dependsOn = [ "supabase-meta" ];
        environment = {
          HOSTNAME = "0.0.0.0";
          STUDIO_PG_META_URL = "http://meta:8080";
          POSTGRES_HOST = pgHost;
          POSTGRES_PORT = pgPort;
          POSTGRES_DB = pgDb;
          POSTGRES_USER_READ_WRITE = "postgres";
          DEFAULT_ORGANIZATION_NAME = "Default Organization";
          DEFAULT_PROJECT_NAME = "Default Project";
          SUPABASE_URL = "http://kong:8000";
          SUPABASE_PUBLIC_URL = cfg.publicUrl;
          PGRST_DB_SCHEMAS = "public,storage,graphql_public";
          # POSTGRES_PASSWORD / PG_META_CRYPTO_KEY / SUPABASE_ANON_KEY /
          # SUPABASE_SERVICE_KEY / AUTH_JWT_SECRET come from the env file.
        };
      };

      # ── kong (the one ingress) ──────────────────────────────────────────────
      supabase-kong = (common "kong") // {
        image = cfg.images.kong;
        dependsOn = [ "supabase-studio" ];
        ports = [
          "${cfg.kong.listenAddress}:${toString cfg.kong.httpPort}:8000/tcp"
          "${cfg.kong.listenAddress}:${toString cfg.kong.httpsPort}:8443/tcp"
        ];
        entrypoint = "/bin/sh";
        cmd = [ "/home/kong/kong-entrypoint.sh" ];
        environment = {
          KONG_DATABASE = "off";
          KONG_DECLARATIVE_CONFIG = "/usr/local/kong/kong.yml";
          KONG_DNS_ORDER = "LAST,A,CNAME";
          KONG_DNS_NOT_FOUND_TTL = "1";
          KONG_PLUGINS = "request-transformer,cors,key-auth,acl,basic-auth,request-termination,ip-restriction,post-function";
          KONG_NGINX_PROXY_PROXY_BUFFER_SIZE = "160k";
          KONG_NGINX_PROXY_PROXY_BUFFERS = "64 160k";
          KONG_PROXY_ACCESS_LOG = "/dev/stdout combined";
          # SUPABASE_ANON_KEY / SUPABASE_SERVICE_KEY / DASHBOARD_USERNAME /
          # DASHBOARD_PASSWORD come from the env file.
        };
        volumes = [
          "${vol}/api/kong.yml:/home/kong/temp.yml:ro"
          "${vol}/api/kong-entrypoint.sh:/home/kong/kong-entrypoint.sh:ro"
        ];
      };
    };
  };
}
