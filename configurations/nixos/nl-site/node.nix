# A fleet node of a site: whatever the typed Dhall says this host is (the
# site's scheduler node is scheduler + CAS shard + worker; the others CAS
# shard + worker). The slow tier is Azure Blob through a SAS URL in the SITE's
# agenix env file; ports open on tailscale0 only (openFirewall), the ring and
# worker_api dial MagicDNS names. The fleet rendered is the FLAKE's
# (examples/fleet.dhall over examples/sites.dhall), one topology for every
# site, and the binary is the site's rev (`package`; null = the fork module's
# default, the `nativelink-nix` input).
{
  site,
  host,
  package,
}:
{ flake, pkgs, lib, ... }:
let
  hn = flake.inputs.hypermodern-nativelink;
in
{
  # The site policy: fleet nodes carry the site's node tag — ring + worker_api
  # among themselves, 4317 to the rig, nothing else.
  hyper-modern-nixos.network.tailscale.tags = [ site.tags.nodes ];

  # The site's CAS env (AZURE_CAS_SAS_URL) is declared by the site-secrets
  # module under the site's name (see ./default.nix).
  hyper-modern-nativelink.siteSecrets.casEnvName = site.casEnvSecret;

  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = host;
    openFirewall = true;
    inherit package;
    extraEnvironmentFiles = [ "/run/agenix/${site.casEnvSecret}" ];
    # The flake's fleet, composed with its sites: the fork module renders
    # `dhallHost` out of it at eval time (IFD, as everywhere in this tree).
    # buildPackages keeps the render an x86_64 build, like the fork module.
    fleetDir = hn.lib.mkFleetDir {
      pkgs = pkgs.buildPackages;
      fleet = hn + "/examples/fleet.dhall";
      sites = hn + "/examples/sites.dhall";
    };
  };

  # ── Telemetry: the flake's contract, into the rig's ClickHouse ─────────────
  # With nativelink.enable the shim stamps identity by port and scrapes
  # 127.0.0.1:50052 + :50051 /metrics (an upstream-dialect binary serves no
  # Prometheus listener; those scrapes are then empty, OTLP carries the
  # metrics). Only nativelink's unit ships logs: a chaos campaign makes it
  # chatty, and the rest of a node's journal is noise on a 128 GiB sink.
  hyper-modern-nixos.observability.otel.agent.journaldUnits = [ "nativelink.service" ];
}
