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
    };

    redis.enable = lib.mkEnableOption "Redis server (off by default)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.postgres.enable {
      services.postgresql = {
        enable = true;
        inherit (cfg.postgres) package ensureDatabases ensureUsers;

        # Bind loopback always; add the tailscale interface address when tailnet
        # access is enabled. listen_addresses takes addresses, not interface
        # names, so resolve the tailscale0 v4 address at runtime is not possible
        # declaratively — instead we bind all addresses ('*') and rely on (a) the
        # box having no public-facing postgres port open and (b) pg_hba below
        # restricting to loopback + the tailnet CIDRs. This is the documented
        # pattern for tailnet-only postgres.
        settings = lib.recursiveUpdate {
          listen_addresses = lib.mkDefault (if cfg.postgres.tailnet.enable then "*" else "localhost");
        } cfg.postgres.settings;

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
    })

    (lib.mkIf cfg.redis.enable { services.redis.servers."".enable = true; })
  ];
}
