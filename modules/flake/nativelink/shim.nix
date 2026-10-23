# The consumer-side couplings the fork's module deliberately does not know
# about: OUR fleet topology, OUR telemetry pipeline, OUR state registry.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.nativelink;
  otelAgent = config.hyper-modern-nixos.observability.otel.agent;

  # ./data with one file overlaid: nix-cache-site.dhall saying this host pushes
  # to R2. The fork's module renders nix-cache.dhall from a Params record it
  # builds from its own options, and a host's standing in the fleet (consumer
  # of the shared tier or one of its producers) is not among them — so the
  # fact rides in the fleetDir, typed, next to the render that reads it. Every
  # other file is a byte-for-byte copy, so the RE fleet renders identically
  # from either directory.
  producerFleetDir =
    pkgs.buildPackages.runCommand "nativelink-fleet-data-producer" { } ''
      cp -r ${./data} "$out"
      chmod -R u+w "$out"
      cp ${pkgs.writeText "nix-cache-site.dhall" "{ pushToR2 = True }\n"} \
        "$out"/nix-cache-site.dhall
    '';
in
{
  options.hyper-modern-nixos.nativelink.extraEnvironmentFiles = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "/run/agenix/nativelink-azure-env" ];
    description = ''
      Extra EnvironmentFiles for the RE service. The fork module only wires the
      R2 credential file; a slow tier on another object store (the Azure soak
      fleet's `AZURE_CAS_SAS_URL`, consumed by the Dhall `azure` backend via
      shellexpand) hands its env file in here. Never store paths.
    '';
  };

  options.hyper-modern-nixos.nativelink.nixCache.pushToR2 = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Make this host a PRODUCER of the shared R2 Nix cache: NARs write back to
      R2 and narinfo + alias records write through, so every other host of the
      fleet serves what this one builds. Off, R2 is read-only for the nix cache
      (misses fill the local tier, nothing is pushed) — the shape a laptop
      uplink needs. Requires `r2.enable`. Implemented by overlaying
      data/nix-cache-site.dhall in the fleetDir (see shim.nix); the RE fleet's
      own write direction is per host in fleet.dhall (`pushToSlow`).
    '';
  };

  config = lib.mkMerge [
    {
      # The typed Dhall fleet definition is this repo's — the module renders
      # whatever fleet it is pointed at. A nix-cache producer gets the same
      # directory with its one per-host fact flipped.
      hyper-modern-nixos.nativelink.fleetDir =
        if cfg.nixCache.pushToR2 then producerFleetDir else lib.mkDefault ./data;

      assertions = [
        {
          assertion = cfg.nixCache.pushToR2 -> cfg.r2.enable;
          message = "hyper-modern-nixos.nativelink.nixCache.pushToR2 needs r2.enable: there is no R2 tier to push to.";
        }
      ];

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
    # Telemetry identity. Both servers are service.name=nativelink with a
    # random instance id per process, and the fork's resource ignores
    # OTEL_RESOURCE_ATTRIBUTES, so a dashboard could not tell the RE
    # scheduler/worker from the nix cache, or either from an ad-hoc dev/chaos
    # nativelink on the same box. Identity by port: each service pushes to its
    # own tagged receiver on the local agent, which stamps nativelink.role and
    # deployment.environment=fleet. Unlabelled nativelink data is not ours.
    (lib.mkIf (otelAgent.enable && (cfg.enable || cfg.nixCache.enable)) {
      hyper-modern-nixos.observability.otel.agent.taggedOtlp =
        lib.optionalAttrs cfg.enable {
          nativelink-re = {
            port = 4321;
            attributes = {
              "nativelink.role" = "re";
              "deployment.environment" = "fleet";
            };
          };
        }
        // lib.optionalAttrs cfg.nixCache.enable {
          nativelink-nix-cache = {
            port = 4322;
            attributes = {
              "nativelink.role" = "nix-cache";
              "deployment.environment" = "fleet";
            };
          };
        };
    })
    (lib.mkIf (otelAgent.enable && cfg.enable) {
      systemd.services.nativelink.environment.NL_OTEL_ENDPOINT = lib.mkForce "http://127.0.0.1:4321";
    })
    (lib.mkIf (cfg.enable && cfg.extraEnvironmentFiles != [ ]) {
      systemd.services.nativelink.serviceConfig.EnvironmentFile = cfg.extraEnvironmentFiles;
    })
    (lib.mkIf (otelAgent.enable && cfg.nixCache.enable) {
      # The fork's module only wires NL_OTEL_ENDPOINT into the RE service; the
      # nix cache was silent. TODO[b7r6]: upstream into the fork's module.
      systemd.services.nativelink-nix-cache.environment.NL_OTEL_ENDPOINT = "http://127.0.0.1:4322";
    })
    (lib.mkIf cfg.nixCache.enable {
      # A reconstructible cache: NARs are re-pushable/re-derivable, so the store
      # is persisted across an impermanence reboot (warm cache) but not backed up.
      hyper-modern-nixos.state.dirs.nativelink-nix-cache = {
        path = cfg.nixCache.stateDir;
        class = "reconstructible";
      };
    })
    (lib.mkIf
      (cfg.nixCache.enable && cfg.nixCache.fetchProxy.enable && cfg.nixCache.fetchProxy.wireNixDaemon)
      {
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
      }
    )
  ];
}
