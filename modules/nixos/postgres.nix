# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                           // hyper-modern-nixos // databases
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# PostgreSQL + Redis, OFF BY DEFAULT.
#
# Previously this module unconditionally enabled postgres on EVERY host. It is
# now opt-in via `hyper-modern-nixos.databases.postgres.enable`, because the
# fleet runs exactly one shared postgres (on watchtower) that backs the central
# atticd cache's metadata. Other hosts don't need a local postgres.
#
# ── Tailnet exposure (best-practice, defense in depth) ──────────────────────
# When `tailnet.enable` is set, exposure is gated at TWO layers:
#   1. firewall: port 5432 is opened ONLY on `tailnet.interface` (tailscale0),
#      via networking.firewall.interfaces. Postgres is more sensitive than a
#      pull cache, so the consuming host should re-enable its firewall
#      (hyper-modern-nixos.network.firewall.enable = true on watchtower) so this
#      interface-scoped rule actually bites — the rest of the fleet runs
#      firewall-off, but the DB host opts back in.
#   2. pg_hba: md5 auth permitted only from loopback + the tailnet CIDRs.
# atticd instances on other hosts connect over MagicDNS.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.databases;
in
{
  options.hyper-modern-nixos.databases = {
    postgres = {
      enable = lib.mkEnableOption "PostgreSQL server (off by default)";

      package = lib.mkPackageOption pkgs "postgresql_16" { };

      tailnet = {
        enable = lib.mkEnableOption ''
          listen on the tailscale0 address and allow md5-authenticated
          connections from the tailnet CGNAT range (100.64.0.0/10)
        '';

        interface = lib.mkOption {
          type = lib.types.str;
          default = "tailscale0";
          description = "Interface whose address postgres additionally binds.";
        };

        cidrs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "100.64.0.0/10" # tailscale CGNAT range (IPv4)
            "fd7a:115c:a1e0::/48" # tailscale ULA range (IPv6)
          ];
          description = "Source CIDRs permitted (md5) in pg_hba for tailnet access.";
        };
      };

      ensureDatabases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "atticd" ];
        description = "Databases to create declaratively (services.postgresql.ensureDatabases).";
      };

      ensureUsers = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [ ];
        description = ''
          Roles to create declaratively (services.postgresql.ensureUsers).
          Peer-auth only by default; for password auth set a password out of
          band (ALTER ROLE … PASSWORD) or via an agenix-fed init — NixOS won't
          put a password in the store.
        '';
      };

      settings = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Extra settings merged into services.postgresql.settings.";
      };

      # ── Declarative role passwords ──────────────────────────────────────────
      # ensureUsers cannot set a password. This wires a post-start oneshot that
      # runs `ALTER ROLE <name> PASSWORD …` for each entry, sourcing the password
      # from an AGENIX SECRET (by name) and taking the named env var. Idempotent
      # on every boot/rebuild; the password is read at runtime and NEVER enters
      # the store. Single source of truth: the SAME secret the client (e.g.
      # atticd) reads PGPASSWORD from, so they can't drift.
      #
      # Purely declarative + host-agnostic: this module GRANTS the postgres user
      # read access to the named secret (age.secrets.<name>.group = "postgres",
      # mode 0440), so the postgres-run oneshot can read it without any manual
      # chown. The secret stays root-owned; atticd reads it via systemd
      # EnvironmentFile (as root, pre-DynamicUser) so group-read doesn't affect it.
      rolePasswords = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              secret = lib.mkOption {
                type = lib.types.str;
                description = "agenix secret NAME (decrypts to /run/agenix/<name>) to source the password from.";
              };
              var = lib.mkOption {
                type = lib.types.str;
                default = "PGPASSWORD";
                description = "Env var name within the secret holding the role password.";
              };
            };
          }
        );
        default = { };
        example = {
          atticd.secret = "atticd-rs256";
        };
        description = "role name -> { secret; var; } to set that role's password declaratively.";
      };
    };

    redis.enable = lib.mkEnableOption "Redis server (off by default)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.postgres.enable {
      services.postgresql = {
        enable = true;
        inherit (cfg.postgres) package ensureDatabases ensureUsers;

        # When tailnet access is enabled, listen on ALL addresses (enableTCPIP is
        # the blessed NixOS knob → listen_addresses = "*"). Exposure is gated by
        # (a) the firewall opening 5432 only on tailscale0 and (b) pg_hba below
        # restricting md5 auth to loopback + the tailnet CIDRs. listen_addresses
        # takes addresses (not interface names), so binding the specific tailscale
        # IP isn't possible declaratively; "*" + firewall + pg_hba is the pattern.
        enableTCPIP = cfg.postgres.tailnet.enable;

        settings = cfg.postgres.settings;

        # Authentication: local peer for admin; md5 over the tailnet for clients.
        authentication = lib.mkIf cfg.postgres.tailnet.enable (
          lib.mkForce (
            ''
              # ── hyper-modern-nixos: tailnet-scoped access ──
              # TYPE  DATABASE  USER  ADDRESS            METHOD
              local   all       all                      peer
              host    all       all   127.0.0.1/32       md5
              host    all       all   ::1/128            md5
            ''
            + lib.concatMapStringsSep "\n" (
              cidr: "host    all       all   ${cidr}        md5"
            ) cfg.postgres.tailnet.cidrs
            + "\n"
          )
        );
      };

      # Open 5432 ONLY on the tailscale interface (layer 1). This bites only if
      # the host's firewall is enabled — watchtower opts back in.
      networking.firewall.interfaces.${cfg.postgres.tailnet.interface} =
        lib.mkIf cfg.postgres.tailnet.enable
          { allowedTCPPorts = [ 5432 ]; };

      # Grant the postgres user read access to each referenced secret, so the
      # postgres-run oneshot below can source it — purely declarative, no manual
      # chown. Root-owned, postgres group, 0440. atticd reads the same file via
      # systemd EnvironmentFile (as root) so this doesn't affect it. Only emitted
      # when rolePasswords is non-empty (so a host without agenix — e.g. a VM
      # test — that doesn't use rolePasswords never touches the age option).
      age.secrets = lib.mkIf (cfg.postgres.rolePasswords != { }) (
        lib.mapAttrs' (
          _role: spec:
          lib.nameValuePair spec.secret {
            group = "postgres";
            mode = "0440";
          }
        ) cfg.postgres.rolePasswords
      );

      # Declaratively set role passwords from agenix secrets, after postgres is
      # up. Idempotent ALTER ROLE; runs as the postgres superuser via peer auth.
      # The password is sourced at runtime (never the store).
      systemd.services.postgresql-role-passwords = lib.mkIf (cfg.postgres.rolePasswords != { }) {
        description = "set postgres role passwords from agenix secrets";
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          RemainAfterExit = true;
        };
        script = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            role: spec:
            let
              pgbin = "${config.services.postgresql.package}/bin/psql";
              envFile = "/run/agenix/${spec.secret}";
              # the literal shell var reference, e.g. $PGPASSWORD
              varRef = "$" + spec.var;
            in
            ''
              if [ -r "${envFile}" ]; then
                # shellcheck disable=SC1090
                pw=$( set -a; . "${envFile}"; printf '%s' "${varRef}" )
                if [ -n "$pw" ]; then
                  ${pgbin} -v ON_ERROR_STOP=1 \
                    -c "ALTER ROLE \"${role}\" WITH LOGIN PASSWORD '$pw';" \
                    || echo "warning: failed to set password for role ${role}" >&2
                else
                  echo "warning: ${spec.var} empty in ${envFile} for role ${role}" >&2
                fi
              else
                echo "warning: secret ${envFile} for role ${role} not readable" >&2
              fi
            ''
          ) cfg.postgres.rolePasswords
        );
      };
    })

    (lib.mkIf cfg.redis.enable { services.redis.servers."".enable = true; })
  ];
}
