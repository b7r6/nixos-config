# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                             // hyper-modern-nixos // topology
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The fleet topology registry — the single source of truth for host identity,
# addressing, and roles. Authored in Dhall (typed + validated at eval), rendered
# to JSON at build time, and exposed here as Nix data + derived query helpers.
# Everything downstream (CoreDNS zones, nginx vhosts, cloudflared ingress) reads
# from `config.hyper-modern-nixos.topology.*`. See
# docs/src/architecture/networking.md and registry/schema.dhall.
#
# Pure data + read-only outputs; this module starts no service. It is always
# imported (cheap), and its `registry`/`hosts`/helper outputs are consumed by
# the networking modules as they land.
{
  config,
  lib,
  flake ? null,
  ...
}:
let
  cfg = config.hyper-modern-nixos.topology;

  inherit (lib)
    mkOption
    types
    filter
    filterAttrs
    listToAttrs
    nameValuePair
    unique
    length
    ;

  # ── Dhall → JSON bridge (committed artifact, NOT import-from-derivation) ─────
  # The registry's source of truth is registry/hosts.dhall (typed + validated by
  # Dhall). It is rendered to a COMMITTED registry/registry.json by the dev
  # command `nix run .#topology-render` (see modules/flake/toplevel.nix), which
  # the topology-check also verifies is in sync. We read that committed JSON
  # rather than rendering at eval time — IFD (runCommand + readFile) breaks under
  # `nix flake check`'s no-build evaluator, and a committed artifact is the
  # standard, IFD-free pattern (like a lockfile). Regenerate after editing Dhall.
  registry = builtins.fromJSON (builtins.readFile (flake.self + "/registry/registry.json"));

  # Host list → attrset keyed by physical name (the NixOS attr name).
  hostsByPhysical = listToAttrs (map (h: nameValuePair h.physical h) registry.hosts);

  managedHosts = filterAttrs (_n: h: h.managed) hostsByPhysical;

  # ── Derived query helpers (other modules consume these) ─────────────────────
  helpers = {
    # Hosts (attrset) running a given service tag.
    hostsWithService = svc: filterAttrs (_n: h: builtins.elem svc h.services) hostsByPhysical;

    # Hosts (attrset) of a coarse role.
    hostsByRole = r: filterAttrs (_n: h: h.role == r) hostsByPhysical;

    # This host's own registry entry (by networking.hostName), or null.
    self = hostsByPhysical.${config.networking.hostName} or null;

    # Fully-qualified tailnet name for a host entry.
    tailnetFqdn = h: "${h.tailnet}.${registry.tailnetSuffix}";
  };

  # ── Validation (belt-and-suspenders on top of Dhall's type checking) ─────────
  # Dhall guarantees well-typedness; these catch SEMANTIC errors Dhall's types
  # can't (duplicate IPs, a host in an undeclared zone, physical≠hostName-able).
  zoneNames = map (z: z.name) registry.zones;
  allTailnetIPs = map (h: h.tailnet_ipv4) registry.hosts;
  dupIPs = unique (filter (ip: length (filter (x: x == ip) allTailnetIPs) > 1) allTailnetIPs);
  badZones = filter (h: !(builtins.elem h.zone zoneNames)) registry.hosts;
in
{
  options.hyper-modern-nixos.topology = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Expose the fleet topology registry (data + helpers). On by default; pure data.";
    };

    validate = mkOption {
      type = types.bool;
      default = true;
      description = "Fail the build on semantic topology errors (dup IPs, unknown zones).";
    };

    registry = mkOption {
      type = types.attrs;
      readOnly = true;
      default = registry;
      description = "DERIVED: the full topology registry (from registry/*.dhall).";
    };

    hosts = mkOption {
      type = types.attrs;
      readOnly = true;
      default = hostsByPhysical;
      description = "DERIVED: hosts keyed by physical (NixOS attr) name.";
    };

    managedHosts = mkOption {
      type = types.attrs;
      readOnly = true;
      default = managedHosts;
      description = "DERIVED: only hosts with managed = true (deployable nixosConfigurations).";
    };

    helpers = mkOption {
      type = types.attrs;
      readOnly = true;
      default = helpers;
      description = "DERIVED: query helpers (hostsWithService, hostsByRole, self, tailnetFqdn).";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.validate) {
    assertions = [
      {
        assertion = dupIPs == [ ];
        message = "topology: duplicate tailnet_ipv4 in registry: ${toString dupIPs}";
      }
      {
        assertion = badZones == [ ];
        message = "topology: hosts in undeclared zones: ${toString (map (h: h.physical) badZones)}";
      }
    ];
  };
}
