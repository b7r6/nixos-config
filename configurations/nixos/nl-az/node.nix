# A fleet node of the Azure site: whatever the typed Dhall says this host is
# (nl-az-a: scheduler + CAS shard + worker; b/c: CAS shard + worker). The slow
# tier is Azure Blob through a SAS URL in the agenix env file; ports open on
# tailscale0 only (openFirewall), the ring and worker_api dial MagicDNS names.
#
# Since 2026-10-14 the binary and the render are the SITE's: the package is
# the flake input sites.dhall names for az (`nativelinkRev`, upstream v1.7.6,
# asserted against the lock like every generated site) and the fleet rendered
# is the flake's examples/fleet.dhall over examples/sites.dhall, whose az
# record carries `dialect = upstream`. nixos-config's own
# modules/flake/nativelink/data is no longer what az boots on; this is the
# first half of the fold-in onto nl-site (docs/azure-soak-fleet.md).
{ name }:
{ flake, pkgs, lib, ... }:
let
  hn = flake.inputs.hypermodern-nativelink;
  site =
    (hn.lib.renderSites {
      pkgs = pkgs.buildPackages;
      sites = hn + "/examples/sites.dhall";
    }).az;
  packageFor = import ../nl-site/package.nix {
    inherit (flake) inputs;
    inherit lib;
  };
in
{
  # nativelink-azure-env (AZURE_CAS_SAS_URL) is declared by the site-secrets
  # module from hypermodern-nativelink (see ./default.nix).
  # The site policy (hypermodern-nativelink netops/tailscale-policy.hujson):
  # fleet nodes carry tag:nl-soak — ring + worker_api among themselves, 4317 to
  # the rig, nothing else.
  hyper-modern-nixos.network.tailscale.tags = [ "tag:nl-soak" ];

  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = name;
    openFirewall = true;
    package = packageFor site;
    extraEnvironmentFiles = [ "/run/agenix/nativelink-azure-env" ];
    # The flake's fleet, composed with its sites (IFD, as everywhere here):
    # the same directory nl-site renders, so az and az2 boot on one topology.
    fleetDir = hn.lib.mkFleetDir {
      pkgs = pkgs.buildPackages;
      fleet = hn + "/examples/fleet.dhall";
      sites = hn + "/examples/sites.dhall";
    };
  };

  # ── Telemetry: the flake's contract, into the rig's ClickHouse ─────────────
  # With nativelink.enable the shim stamps identity by port (4321 →
  # nativelink.role=re) and scrapes 127.0.0.1:50052 + :50051 /metrics (empty
  # on an upstream-dialect binary, which serves no Prometheus listener; OTLP
  # carries the metrics); what is left is which logs ship. Only nativelink's
  # unit: a chaos campaign makes it chatty, and the rest of a node's journal
  # is noise on a 128 GiB sink.
  hyper-modern-nixos.observability.otel.agent.journaldUnits = [ "nativelink.service" ];
}
