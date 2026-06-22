# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // coredns
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Split-horizon DNS for the fleet, OFF BY DEFAULT. Authoritative for the internal
# zone (sju1.s4.gl), forwards everything else out. The zone is GENERATED from the
# topology registry (hyper-modern-nixos.topology) — never hand-written — so it
# can't drift from the source of truth. See
# docs/src/architecture/networking.md.
#
# Addressing modes served (all from the registry):
#   <host>.<dc>.s4.gl       A → tailnet_ipv4   (the overlay/fleet path)
#   <host>.lan.<dc>.s4.gl   A → lan_ipv4       (LAN devices, e.g. a Google TV →
#                                               Jellyfin; only hosts with a lease)
#   <service>.<dc>.s4.gl    CNAME → the host running that service tag
#
# Built on the stock services.coredns (systemd unit + hardening come from there);
# this module only generates the Corefile + zone file from the registry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.coredns;
  topo = config.hyper-modern-nixos.topology;

  inherit (lib)
    mkOption
    mkEnableOption
    types
    concatStringsSep
    concatMapStringsSep
    filter
    attrValues
    optionalString
    ;

  hosts = attrValues topo.hosts;

  # The internal zone is the DC subdomain of the internal domain: <dc>.<domain>.
  # Single-site today (one dc), so one zone. (Multi-DC later = one zone per dc.)
  zone = "${cfg.dc}.${topo.registry.internalDomain}";

  # ── Zone file body, generated from the registry ─────────────────────────────
  # A-records: <host> → tailnet_ipv4 for every host; <host>.lan → lan_ipv4 for
  # hosts that have a static lease (Optional → rendered absent when null, so we
  # filter on its presence).
  hostRecords = concatMapStringsSep "\n" (h: "${h.physical} IN A ${h.tailnet_ipv4}") hosts;

  lanRecords = concatMapStringsSep "\n" (h: "${h.physical}.lan IN A ${h.lan_ipv4}") (
    filter (h: h ? lan_ipv4 && h.lan_ipv4 != null) hosts
  );

  # Service CNAMEs: for each service tag → the (first) host running it. e.g.
  # registry.<zone> → watchtower. Used so clients can name a service, not a box.
  allServices = lib.unique (lib.concatMap (h: h.services) hosts);
  serviceRecords = concatMapStringsSep "\n" (
    svc:
    let
      providers = filter (h: builtins.elem svc h.services) hosts;
      target = (builtins.head providers).physical;
    in
    optionalString (providers != [ ]) "${svc} IN CNAME ${target}.${zone}."
  ) allServices;

  zoneFile = pkgs.writeText "${zone}.zone" ''
    $TTL ${toString cfg.ttl}
    $ORIGIN ${zone}.
    @ IN SOA ns.${zone}. admin.${zone}. (
        ${cfg.serial} ; serial
        3600          ; refresh
        1800          ; retry
        604800        ; expire
        ${toString cfg.ttl} ; minimum
    )
    @ IN NS ns.${zone}.
    ns IN A ${cfg.selfTailnetIPv4}

    ; ── hosts: <host>.${zone} → tailnet_ipv4 ──
    ${hostRecords}

    ; ── LAN: <host>.lan.${zone} → lan_ipv4 (static-leased wired boxes only) ──
    ${lanRecords}

    ; ── service aliases: <service>.${zone} → host running it ──
    ${serviceRecords}
  '';

  corefile = pkgs.writeText "Corefile" ''
    ${zone}:${toString cfg.port} {
        bind ${cfg.bindAddress}
        file ${zoneFile} ${zone}
        ${optionalString cfg.prometheus "prometheus ${cfg.bindAddress}:9153"}
        errors
        ${optionalString cfg.debug "log"}
    }

    .:${toString cfg.port} {
        bind ${cfg.bindAddress}
        forward . ${concatStringsSep " " cfg.forwardServers} {
            health_check 5s
        }
        cache ${toString cfg.cacheTTL}
        ${optionalString cfg.prometheus "prometheus ${cfg.bindAddress}:9153"}
        errors
        ${optionalString cfg.debug "log"}
    }
  '';
in
{
  options.hyper-modern-nixos.coredns = {
    enable = mkEnableOption "split-horizon CoreDNS generated from the topology registry";

    dc = mkOption {
      type = types.str;
      default = "sju1";
      description = "DC subdomain this node serves the internal zone for (<dc>.<internalDomain>).";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = ''
        Address CoreDNS binds. 0.0.0.0 so both tailnet and LAN clients can resolve
        (the Google TV reaches it on the LAN; fleet boxes over tailscale0). The
        firewall opens 53 — see openFirewall.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 53;
      description = "DNS port.";
    };

    selfTailnetIPv4 = mkOption {
      type = types.str;
      default = if topo.helpers.self != null then topo.helpers.self.tailnet_ipv4 else "";
      defaultText = "the running host's tailnet_ipv4 from the topology registry";
      description = ''
        This resolver host's tailnet IPv4, used for the zone's NS glue record.
        Defaults to the host's own entry in the topology registry (single source);
        only set explicitly for a resolver not in the registry.
      '';
    };

    forwardServers = mkOption {
      type = types.listOf types.str;
      default = [
        "100.100.100.100" # tailscale MagicDNS first (so *.ts.net resolves)
        "1.1.1.1"
        "8.8.8.8"
      ];
      description = "Upstreams for non-internal names (MagicDNS first).";
    };

    ttl = mkOption {
      type = types.int;
      default = 300;
      description = "Zone record TTL / SOA minimum.";
    };

    serial = mkOption {
      type = types.str;
      default = "1";
      description = "SOA serial. The zone file is content-addressed by Nix, so bumping is optional.";
    };

    cacheTTL = mkOption {
      type = types.int;
      default = 3600;
      description = "Forward-path cache TTL (seconds).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Open port 53 (tcp+udp). On a LAN-reachable resolver this must include the LAN, so it opens on all interfaces (not just tailscale0).";
    };

    prometheus = mkOption {
      type = types.bool;
      default = true;
      description = "Expose CoreDNS Prometheus metrics on :9153.";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable CoreDNS query logging.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.selfTailnetIPv4 != "";
        message = "hyper-modern-nixos.coredns.enable is true but selfTailnetIPv4 is unset (needed for the zone NS glue).";
      }
    ];

    services.coredns = {
      enable = true;
      config = builtins.readFile corefile;
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.port ];
      allowedUDPPorts = [ cfg.port ];
    };
  };
}
