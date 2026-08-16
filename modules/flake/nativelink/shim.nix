# The consumer-side couplings the fork's module deliberately does not know
# about: OUR fleet topology, OUR telemetry pipeline, OUR state registry.
{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.nativelink;
  otelAgent = config.hyper-modern-nixos.observability.otel.agent;
in
{
  config = lib.mkMerge [
    {
      # The typed Dhall fleet definition is this repo's — the module renders
      # whatever fleet it is pointed at.
      hyper-modern-nixos.nativelink.fleetDir = lib.mkDefault ./data;

      # Point nativelink's OTLP push at the host-local otel agent, like every
      # other fleet service (the fork module defaults this to null).
      hyper-modern-nixos.nativelink.otlpEndpoint = lib.mkDefault (
        if otelAgent.enable then "http://127.0.0.1:${toString otelAgent.localOtlpPort}" else null
      );
    }
    (lib.mkIf cfg.enable {
      # nativelink's local store is a reconstructible CAS: content is R2-backed or
      # re-derivable, so it's persisted across an impermanence reboot (warm cache)
      # but NOT backed up to R2 — paying to back up re-creatable CAS is waste.
      hyper-modern-nixos.state.dirs.nativelink = {
        path = "/var/lib/nativelink";
        class = "reconstructible";
      };

      # Scrape nativelink's Prometheus /metrics (services.experimental_prometheus,
      # enabled in the Dhall for the cas + public servers) into the OTel pipeline:
      # store fill/eviction from the cas server (:50052), scheduler/worker state
      # from the public server (:50051, only up on the scheduler — a down target
      # is harmless).
      hyper-modern-nixos.observability.otel.agent.scrapeTargets = [
        "127.0.0.1:50052"
        "127.0.0.1:50051"
      ];
    })
    (lib.mkIf cfg.nixCache.enable {
      # A reconstructible cache: NARs are re-pushable/re-derivable, so the store
      # is persisted across an impermanence reboot (warm cache) but not backed up.
      hyper-modern-nixos.state.dirs.nativelink-nix-cache = {
        path = cfg.nixCache.stateDir;
        class = "reconstructible";
      };
    })
    (lib.mkIf (cfg.nixCache.enable && cfg.nixCache.fetchProxy.enable && cfg.nixCache.fetchProxy.wireNixDaemon) {
      # Extend the fork's fetch-proxy bypass list with github: git-based FODs
      # (fetchgit, e.g. a cargo git dep) use git's libcurl, which — unlike the
      # OpenSSL fetchurl path that trusts the nix-only CA bundle — cannot load
      # the proxy's `NativeLink CAS Witness CA` cert (curl errors "adding trust
      # anchors from file"), so a MITM'd github fetch dies with "unable to get
      # local issuer certificate (20)". Bypassing sends git straight to github
      # with its real cert, verified by the stock system CAs. codeload/
      # objects.githubusercontent.com ride along for tarball + LFS/release-asset
      # FODs from the same origin.
      # TODO[b7r6]: upstream into the fork's fetchProxyNoProxy, then delete.
      systemd.services.nix-daemon.environment =
        let
          noProxy = "127.0.0.1,localhost,::1,cache.nixos.org,nix-community.cachix.org,nix-postgres-artifacts.s3.amazonaws.com,github.com,codeload.github.com,objects.githubusercontent.com";
        in
        {
          no_proxy = lib.mkForce noProxy;
          NO_PROXY = lib.mkForce noProxy;
        };
    })
  ];
}
