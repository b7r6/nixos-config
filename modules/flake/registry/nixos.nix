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
  pkgs,
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

  # ── Dhall → Nix values, directly at eval via IFD ─────────────────────────────
  # The registry's source of truth is registry/hosts.dhall (typed + validated by
  # Dhall). We render it to JSON and read it back AT EVAL TIME — import-from-
  # derivation, enabled fleet-wide (see nix.nix). No committed registry.json, no
  # render/check staleness dance. The registry Dhall is fully local (no remote
  # Prelude), so the build needs only the locale fix (unicode in comments), not
  # CA certs. buildPackages so cross-arch shimmer doesn't demand an aarch64 build.
  registrySrc = flake.self + "/modules/flake/registry/data";
  buildPkgs = pkgs.buildPackages;

  registry = builtins.fromJSON (
    builtins.readFile (
      buildPkgs.runCommand "registry.json"
        {
          nativeBuildInputs = [ buildPkgs.dhall-json ];
          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";
          LOCALE_ARCHIVE = "${buildPkgs.glibcLocales}/lib/locale/locale-archive";
        }
        ''
          dhall-to-json --file ${registrySrc}/hosts.dhall > "$out"
        ''
    )
  );

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
