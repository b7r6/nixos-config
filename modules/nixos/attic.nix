# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                               // hyper-modern-nixos // attic
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# attic.rs binary cache server (atticd), OFF BY DEFAULT.
#
# Uses the in-nixpkgs `pkgs.attic-server` + the upstream-maintained
# `services.atticd` NixOS module (already in our pinned nixpkgs) — NO new flake
# input required. Verified to build from the binary cache in this nixpkgs rev.
#
# Defaults: monolithic mode, sqlite at /var/lib/atticd/server.db, local storage
# at /var/lib/atticd/storage. Switch to postgres/S3 via `settings` if/when you
# outgrow that (postgres is already available via common/postgres.nix).
#
# ── Fleet topology (replicated api-server + shared state) ───────────────────
# Per the attic docs, atticd splits cleanly:
#   - api-server: STATELESS, can be replicated. We run one per host.
#   - garbage-collector: CANNOT be replicated. Exactly one node runs it.
#   - monolithic: runs everything (api-server + gc); single-node only.
# Shared state lives OUTSIDE atticd: postgres (on watchtower) holds metadata,
# an R2 bucket holds the content-addressed NAR/chunk store. Dedup is global, so
# every host's local api-server reads/writes the same logical cache. Each host
# points its nix substituters at its OWN localhost:8080 (no serialization
# through one box), while the truth is shared. The RS256 signing secret MUST be
# identical on every node so JWTs verify fleet-wide.
#
#   watchtower:     mode = "monolithic"  (api-server + the single GC) + postgres
#   every other:    mode = "api-server"  (stateless; same pg + R2 + RS256)
#
# Secret (REQUIRED when enabled): atticd needs an RS256 JWT signing secret,
# provided via an env file. It MUST be a single-line var (systemd
# EnvironmentFile cannot parse a multi-line PEM), so we base64 the key:
#
#   ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(openssl genrsa -traditional 4096 | base64 -w0)
#
# The SAME env file also carries (none of which may touch the store):
#   PGPASSWORD=<postgres password for the atticd role>   (sqlx reads it)
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY            (R2 chunk-store creds)
# The passwordless connection string itself (postgresql://atticd@host/atticd) is
# non-secret and set via hyper-modern-nixos.attic.databaseUrl.
#
# Generate once, store it with agenix as `atticd-rs256.age`, and wire
# `age.secrets.atticd-rs256` to decrypt it. This module points
# `services.atticd.environmentFile` at that decrypted path. Inert until enabled.

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.attic;
in
{
  options.hyper-modern-nixos.attic = {
    enable = lib.mkEnableOption "atticd nix binary cache server (off by default)";

    mode = lib.mkOption {
      type = lib.types.enum [
        "monolithic"
        "api-server"
        "garbage-collector"
      ];
      default = "monolithic";
      description = ''
        atticd run mode. In the fleet topology, watchtower runs "monolithic"
        (api-server + the single garbage collector) and every other host runs
        "api-server" (stateless replica). Only ONE node may run gc, so only the
        monolithic node (or a dedicated "garbage-collector" node) collects.
      '';
    };

    databaseUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "postgresql://atticd@watchtower.osiris-walleye.ts.net/atticd";
      description = ''
        PASSWORDLESS postgres connection string for the shared backend. attic
        uses sea-orm + sqlx-postgres, and sqlx honours libpq env vars — so the
        password is supplied SEPARATELY via PGPASSWORD in the environmentFile and
        never enters the store. When null, atticd keeps its local sqlite default.

        NOTE: the URL must NOT contain a password (that would leak into the Nix
        store via the rendered config file). Put PGPASSWORD=<pw> in the
        environmentFile alongside the RS256 secret and R2 creds.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/agenix/atticd-rs256";
      description = ''
        Path to the env file defining ATTIC_SERVER_TOKEN_RS256_SECRET. A host
        that enables attic should declare `age.secrets.atticd-rs256`
        (file = atticd-rs256.age), import the agenix nixos module, and set this
        to that decrypted runtime path. Must NOT be a store path.
      '';
    };

    listen = lib.mkOption {
      type = lib.types.str;
      default = "[::]:8080";
      example = "[::1]:8080";
      description = ''
        Address atticd binds. Default binds all interfaces but the port is only
        opened on `trustedInterfaces` (tailscale0) — so it's reachable across
        the tailnet, not the public internet. Set to [::1]:8080 for loopback.
      '';
    };

    trustedInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "tailscale0" ];
      description = ''
        Interfaces on which the atticd port is opened. Defaults to the tailscale
        interface so the cache is tailnet-only. The listen address can be
        all-interfaces; exposure is gated here at the firewall.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the atticd listen port, but only on trustedInterfaces (tailscale0 by default).";
    };

    # ── Storage backend ───────────────────────────────────────────────────────
    # Local filesystem by default; set type = "s3" for an S3-compatible backend
    # like Cloudflare R2. atticd reads AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
    # from `environmentFile` (the same agenix env file as the RS256 secret), so
    # no credentials touch the nix store. The bucket+endpoint+region are not
    # secret. atticd OWNS the whole bucket (nar/, chunks, …) — give it a
    # dedicated bucket.
    storage = {
      type = lib.mkOption {
        type = lib.types.enum [
          "local"
          "s3"
        ];
        default = "local";
        description = "atticd storage backend.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/atticd/storage";
        description = "Local storage directory (type = local).";
      };

      region = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = "S3 region. R2 is region-agnostic; use \"auto\".";
      };

      bucket = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "straylight-attic-cache";
        description = "S3 bucket name (type = s3). atticd owns the whole bucket.";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "https://<acct>.r2.cloudflarestorage.com";
        description = "Custom S3 endpoint for S3-compatible backends (R2/Minio).";
      };
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Extra settings merged into services.atticd.settings (TOML). e.g. database.url, storage.";
    };

    # ── Client side: make this (or any) host USE an attic cache ───────────────
    # Wires the cache as a substituter (consulted first, the documented NixOS
    # pattern), trusts its public key, and runs `attic watch-store` to auto-push
    # new store paths. Can be enabled on hosts that do NOT run atticd (point
    # endpoint at the server over the tailnet). Pull is anonymous for a public
    # cache; push uses the JWT in pushTokenFile.
    clientCache = {
      enable = lib.mkEnableOption "use an attic cache as substituter + watch-store auto-push";

      name = lib.mkOption {
        type = lib.types.str;
        default = "hypermodern";
        description = "Attic cache name (the URL path segment).";
      };

      endpoint = lib.mkOption {
        type = lib.types.str;
        example = "http://ultraviolence.risk-nunki.ts.net:8080";
        description = "Base atticd URL (no trailing slash, no cache name).";
      };

      publicKey = lib.mkOption {
        type = lib.types.str;
        example = "hypermodern:x+kBunu5nD1KOhzCIawyZeq8w0LV0GC6A7suIRoHTm8=";
        description = "The cache's binary-cache public key (from `attic cache info`).";
      };

      priority = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = ''
          Substituter priority. LOWER = consulted earlier. Default 10 beats
          cache.nixos.org (40) and nix-community (~40), so this cache is tried
          first.
        '';
      };

      pushTokenFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/agenix/attic-push-token";
        description = ''
          Optional path to a file containing a raw attic push JWT (a token with
          push access to `name`). Referenced by the generated attic client
          config as `token-file`, so the secret never enters the store. When
          null, the watch-store auto-push service is not started (pull-only).
          NEVER a store path.
        '';
      };
    };
  };

  config = lib.mkMerge [
    # ── Server (atticd) ────────────────────────────────────────────────────────
    (lib.mkIf cfg.enable {
      # atticd's local state is a reconstructible chunk cache: the authoritative
      # chunks live in R2 (or are re-pushable), so it's persisted across an
      # impermanence reboot (avoid a cold cache) but NOT backed up to R2.
      hyper-modern-nixos.state.dirs.atticd = {
        path = "/var/lib/atticd";
        class = "reconstructible";
      };

      assertions = [
        {
          assertion = cfg.environmentFile != null;
          message = ''
            hyper-modern-nixos.attic.enable is true but no environmentFile is set
            and no agenix secret `atticd-rs256` is defined. atticd needs an RS256
            JWT secret as a SINGLE-LINE env var. Generate one:
              echo "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(openssl genrsa -traditional 4096 | base64 -w0)"
            store it via agenix as atticd-rs256.<host>.age, and wire age.secrets.
          '';
        }
        {
          assertion = cfg.storage.type != "s3" || (cfg.storage.bucket != "" && cfg.storage.endpoint != "");
          message = ''
            hyper-modern-nixos.attic.storage.type = "s3" but bucket/endpoint are
            unset. Set storage.bucket and storage.endpoint, and put
            AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY in the environmentFile.
          '';
        }
      ];

      services.atticd = {
        enable = true;
        inherit (cfg) environmentFile mode;
        settings = lib.recursiveUpdate (
          {
            inherit (cfg) listen;
            storage =
              if cfg.storage.type == "s3" then
                {
                  type = "s3";
                  inherit (cfg.storage) region bucket endpoint;
                  # credentials come from AWS_* in environmentFile (not here).
                }
              else
                {
                  type = "local";
                  inherit (cfg.storage) path;
                };
          }
          # Shared postgres backend: set a PASSWORDLESS connection string in
          # the config file (non-secret), overriding the upstream sqlite
          # mkDefault. sqlx reads the password from PGPASSWORD in the
          # environmentFile, so no secret enters the store.
          // lib.optionalAttrs (cfg.databaseUrl != null) { database.url = lib.mkForce cfg.databaseUrl; }
        ) cfg.settings;
      };

      # Client CLI for `attic login` / `attic push` / `attic use`.
      environment.systemPackages = [ pkgs.attic-client ];

      # If this node sets local postgres role passwords (monolithic-shared on
      # the pg host), atticd must wait for that oneshot — otherwise it races the
      # password being set and crash-loops on md5 auth until the next restart.
      # Condition on the INPUT option (not config.systemd.services, which would
      # recurse while defining systemd.services.atticd).
      systemd.services.atticd =
        lib.mkIf (config.hyper-modern-nixos.databases.postgres.rolePasswords != { })
          {
            after = [ "postgresql-role-passwords.service" ];
            wants = [ "postgresql-role-passwords.service" ];
          };

      # Open the port ONLY on the trusted (tailscale) interfaces, so the cache
      # is tailnet-reachable but not exposed to the public internet even though
      # atticd binds all interfaces.
      networking.firewall = lib.mkIf cfg.openFirewall (
        let
          port = lib.toInt (lib.last (lib.splitString ":" cfg.listen));
        in
        {
          interfaces = lib.genAttrs cfg.trustedInterfaces (_: {
            allowedTCPPorts = [ port ];
          });
        }
      );
    })

    # ── Client (use a cache as substituter + auto-push) ─────────────────────────
    (lib.mkIf cfg.clientCache.enable {
      nix.settings = {
        # Consulted FIRST: prepended, and given a lower (= higher) priority via
        # ?priority= so nix tries it before cache.nixos.org.
        substituters = lib.mkBefore [
          "${cfg.clientCache.endpoint}/${cfg.clientCache.name}?priority=${toString cfg.clientCache.priority}"
        ];
        trusted-public-keys = [ cfg.clientCache.publicKey ];
      };

      # Auto-populate via the canonical `attic watch-store` daemon (docs:
      # user-guide). It watches the store and uploads NEW paths continuously —
      # strictly better than a post-build-hook: catches built AND substituted/
      # copied-in paths, runs async (not in the build critical path), and needs
      # no OUT_PATHS plumbing. Only started when a push token is provided.
      #
      # Auth: we hand it a dedicated attic client config via XDG_CONFIG_HOME
      # whose only secret is a `token-file` reference (the agenix path), so the
      # JWT never enters the nix store. Endpoint is non-secret.
      systemd.services.atticd-watch-store = lib.mkIf (cfg.clientCache.pushTokenFile != null) (
        let
          atticConfig = pkgs.writeText "attic-config.toml" ''
            default-server = "${cfg.clientCache.name}"

            [servers.${cfg.clientCache.name}]
            endpoint = "${cfg.clientCache.endpoint}"
            token-file = "${toString cfg.clientCache.pushTokenFile}"
          '';
          atticConfigHome = pkgs.runCommand "attic-config-home" { } ''
            mkdir -p $out/attic
            cp ${atticConfig} $out/attic/config.toml
          '';
        in
        {
          description = "attic watch-store: auto-push new store paths to ${cfg.clientCache.name}";
          wantedBy = [ "multi-user.target" ];
          # Order after tailscale so the cache's MagicDNS endpoint resolves;
          # otherwise the service races DNS at boot and crash-loops on NXDOMAIN.
          after = [
            "network-online.target"
            "tailscaled.service"
          ];
          wants = [
            "network-online.target"
            "tailscaled.service"
          ];
          environment.XDG_CONFIG_HOME = "${atticConfigHome}";
          serviceConfig = {
            ExecStart = "${pkgs.attic-client}/bin/attic watch-store ${cfg.clientCache.name}";
            Restart = "on-failure";
            RestartSec = 10;
            # best-effort: a dead cache must never wedge the box
            DynamicUser = false;
          };
        }
      );

      environment.systemPackages = [ pkgs.attic-client ];
    })
  ];
}
