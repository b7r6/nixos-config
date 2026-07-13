# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hypermodern // nix // nativelink
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# NativeLink remote-execution / remote-cache, OFF BY DEFAULT.
#
# There is NO upstream NixOS module for NativeLink (its flake only ships
# bazelrc-generators), so this is a hand-rolled systemd service around the
# `nativelink` binary from the flake input. The binary takes a single JSON5
# config path argument.
#
# Multi-arch RE: remote execution runs NATIVE binaries, so you need one native
# worker per architecture. The intended topology:
#
#   - role = "monolithic" on an x86_64 host (e.g. ultraviolence): CAS + scheduler
#     + an x86_64 worker. Exposes the public API (50051) and worker_api (50061).
#   - role = "worker"     on shimmer (aarch64 DGX): an aarch64-only worker that
#     dials the monolithic host's worker_api over the tailnet.
#
# ── THE TOOLCHAIN PROBLEM (read this before expecting remote EXECUTION) ──────
#
# Standing up CAS+scheduler+worker (this module) is the easy part. Making remote
# ACTIONS actually execute correctly is the hard part, and it is NOT a server
# concern — it lives in the CLIENT (Buck2/Bazel) repo:
#
#   1. Property matching: the scheduler matches an action's requested platform
#      properties against what a worker advertises (workerProperties +
#      cpu_arch/OSFamily/ISA/container-image/lre-rs, see below). Request a
#      property no worker advertises -> the action never schedules. This routes
#      work; it does NOT make it reproducible.
#
#   2. Hermeticity: a remote worker runs the action's command on ITS filesystem.
#      If the action says `/usr/bin/gcc`, you get the worker's gcc (or none) —
#      non-reproducible or broken. The fix (per NativeLink's LRE docs) is a
#      content-addressed toolchain: every tool referenced is a `/nix/store/...`
#      path. Because our workers ARE NixOS and share /nix/store, a Buck2 toolchain
#      that points at nix-store binaries is hermetic AND cache-shareable: the
#      action hash matches everywhere. A toolchain that references FHS paths is
#      not. THIS is "the trick" with NativeLink.
#
#   3. Buck2 specifics (see configurations/.../README or the host comment):
#      .buckconfig sets engine/action_cache/cas_address + tls=false +
#      instance_name=main (matches `instanceName` here); an ExecutionPlatformInfo
#      with remote_enabled=True; remote_execution_use_case="buck2-default".
#
# This module gets the SERVER right (instance_name, the full property set Buck2
# negotiates, the worker advertisement). The hermetic toolchain is per-repo.
#
# The scheduler matches actions to workers by the platform properties; cpu_arch/
# OSFamily/ISA/container-image/lre-rs are derived from the host, the rest come
# from `workerProperties`.
#
# Build note: NativeLink is not in nixpkgs and builds ~640 derivations from
# source. Add nativelink.cachix.org to nix.settings.substituters before enabling
# on any host, or expect a very long first build.
#
# Nothing here is active until a host sets enable = true, so this module is inert
# and cannot brick a box.
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.hyper-modern-nixos.nativelink;
  inherit (flake) inputs;

  nativelinkPkg =
    if cfg.package != null then
      cfg.package
    else
      inputs.nativelink.packages.${pkgs.stdenv.hostPlatform.system}.nativelink;

  # Local store root (matches storeRoot in nativelink/fleet.dhall); used by the
  # systemd tmpfiles / service wiring below.
  storeRoot = "/var/lib/nativelink";

  # ── Config source: the TYPED Dhall fleet, rendered at eval via IFD ──────────

  # nativelink/fleet.dhall IS the real program: it computes each host's config as
  # a typed schema.Config and renders it (render.dhall, JSON.render). We render it
  # at eval time via import-from-derivation (enabled fleet-wide; see nix.nix) — no
  # committed out/*.json, no render/check staleness dance, no nixlang config
  # generation. `render-all.dhall` emits [{host, json}]; we select this host's
  # entry by name with jq (the .json is already-rendered JSON text) and write it.
  #
  # buildPackages keeps the render an x86_64 build, so a cross-arch host (aarch64
  # shimmer) doesn't demand an aarch64 dhall build at eval; the config text is
  # host-independent given the host name.
  buildPkgs = pkgs.buildPackages;
  fleetDir = flake.self + "/modules/flake/nativelink/data";

  renderedConfig =
    buildPkgs.runCommand "nativelink-${cfg.dhallHost}.json"
      {
        nativeBuildInputs = [
          buildPkgs.dhall-json
          buildPkgs.jq
          buildPkgs.cacert
        ];
        LANG = "C.UTF-8";
        LC_ALL = "C.UTF-8";
        LOCALE_ARCHIVE = "${buildPkgs.glibcLocales}/lib/locale/locale-archive";
        SSL_CERT_FILE = "${buildPkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      }
      ''
        export XDG_CACHE_HOME="$TMPDIR/dhall-cache"
        export HOME="$TMPDIR"
        mkdir -p "$XDG_CACHE_HOME"
        host=${lib.escapeShellArg cfg.dhallHost}
        json=$(dhall-to-json --file ${fleetDir}/render-all.dhall \
                 | jq -e --arg h "$host" '.[] | select(.host==$h) | .json' -r)
        if [ -z "$json" ]; then
          echo "nativelink: host '$host' not found in the Dhall fleet (render-all)" >&2
          exit 1
        fi
        # validate it's well-formed JSON before accepting it
        printf '%s' "$json" | jq . > "$out"
      '';

  # Config source: operator escape hatch, else the rendered typed-Dhall config.
  configFile = if cfg.configFile != null then cfg.configFile else renderedConfig;

  # ── Nix binary cache (substituter) ──────────────────────────────────────────

  # A SECOND, independent nativelink instance serving the Nix HTTP binary-cache
  # protocol from the straylight fork (inputs.nativelink-nix, which carries the
  # nix_cache service upstream lacks). Its config is a trivial 3-store + 1-service
  # JSON5, generated here in Nix — no Dhall fleet involved. Runs alongside the RE
  # service and attic.
  nixCachePkg =
    if cfg.nixCache.package != null then
      cfg.nixCache.package
    else
      inputs.nativelink-nix.packages.${pkgs.stdenv.hostPlatform.system}.nativelink;

  nixCacheFsStore = sub: caps: {
    filesystem = {
      content_path = "${cfg.nixCache.stateDir}/${sub}/content";
      temp_path = "${cfg.nixCache.stateDir}/${sub}/temp";
      eviction_policy.max_bytes = caps;
    };
  };

  # NAR blobs are digest-keyed and wrapped in verify (reject corrupt/truncated
  # uploads at write time). path-info + alias are string-keyed and MUST be
  # separate stores; path-info is completeness_checking-wrapped so an evicted NAR
  # reads as a clean 404 miss instead of a dangling narinfo; alias must NOT sit
  # behind completeness_checking. Keys are slash-free, so filesystem is safe.
  nixCacheConfig = {
    stores = [
      {
        name = "NIX_NAR_STORE";

        verify = {
          verify_size = true;
          verify_hash = true;
          backend = nixCacheFsStore "nar" cfg.nixCache.maxNarBytes;
        };
      }
      {
        name = "NIX_PATH_INFO_STORE";

        completeness_checking = {
          backend = nixCacheFsStore "path-info" 1073741824; # 1 GiB of records
          cas_store.ref_store.name = "NIX_NAR_STORE";
        };
      }

      ({ name = "NIX_ALIAS_STORE"; } // nixCacheFsStore "alias" 1073741824)
    ];

    servers = [
      {
        name = "nix-cache";
        listener.http.socket_address = cfg.nixCache.listen;
        services = {
          health = { };

          nix_cache = [
            (
              {
                instance_name = cfg.nixCache.instanceName;
                cas_store = "NIX_NAR_STORE";
                path_info_store = "NIX_PATH_INFO_STORE";
                alias_store = "NIX_ALIAS_STORE";
                store_dir = cfg.nixCache.storeDir;
                priority = cfg.nixCache.priority;

                # Per-upload cap: an upload whose UNCOMPRESSED NAR exceeds this
                # is rejected with 413 (it also bounds the decompress spool of a
                # compressed upload — a bomb guard). Raise for large artifacts.
                max_nar_size_bytes = cfg.nixCache.maxNarUploadBytes;
              }
              // lib.optionalAttrs (cfg.nixCache.signingKeyFile != null) {
                signing_key_files = [ cfg.nixCache.signingKeyFile ];
              }
            )
          ];
        };
      }
    ];
    global.max_open_files = 24576;
  };

  # JSON is valid JSON5; the binary takes the path as its single argument.
  nixCacheConfigFile = pkgs.writeText "nativelink-nix-cache.json" (builtins.toJSON nixCacheConfig);

  nixCachePort = lib.last (lib.splitString ":" cfg.nixCache.listen);
in
{
  options.hyper-modern-nixos.nativelink = {
    enable = lib.mkEnableOption "NativeLink remote execution / cache (off by default)";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;

      defaultText = lib.literalExpression "inputs.nativelink.packages.\${system}.nativelink";

      description = "NativeLink package. Defaults to the flake input for this host's architecture.";
    };

    role = lib.mkOption {
      type = lib.types.enum [
        "monolithic"
        "scheduler"
        "worker"
      ];

      default = "monolithic";

      description = ''
        monolithic = CAS + scheduler + local worker (single x86_64 host).
        scheduler  = CAS + scheduler only (workers dial in from other hosts).
        worker     = local worker only; dials workerApiEndpoint (use on aarch64).
        IGNORED when dhallHost is set (the typed fleet config decides the roles).
      '';
    };

    # ── Dhall fleet config (the source of truth) ────────────────────────────────

    # When set, render this host's NativeLink config from the typed Dhall fleet
    # (nativelink/fleet.dhall) at eval time via IFD. The Dhall fleet encodes the
    # sharded multi-arch topology (scheduler@watchtower, 4-node weighted CAS ring,
    # per-arch workers). See docs/infrastructure/nativelink-production.md.
    dhallHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "watchtower";

      description = "Fleet host name whose typed Dhall config to run (null = legacy role generator).";
    };

    instanceName = lib.mkOption {
      type = lib.types.str;
      default = "main";

      description = ''
        RE-API instance name served on the public gRPC services. MUST match the
        client. Buck2's `.buckconfig` uses `instance_name = main` and the
        upstream Buck2 integration test uses "main", so that's the default.
        (Bazel/Buck2 clients send this with every request; a mismatch surfaces
        as instance-name errors and zero cache hits.)
      '';
    };

    # ── Telemetry: OTLP push to the local otel collector ──────────────────────
    # This nativelink build has NO Prometheus /metrics scrape endpoint — the
    # `admin` service only exposes /admin/scheduler/.../set_drain_worker. Metrics
    # (and traces) are emitted via OTLP gRPC, but ONLY when the NL_OTEL_ENDPOINT
    # env var is set (nativelink-util/src/telemetry.rs: no endpoint → no exporter
    # → silent no-op). So without this the dashboards can only count journald log
    # lines. Point it at the host-local otel agent's OTLP receiver and the
    # metrics flow agent → gateway → ClickHouse like every other fleet service.
    otlpEndpoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        let
          otelAgent = config.hyper-modern-nixos.observability.otel.agent;
        in
        if otelAgent.enable then "http://127.0.0.1:${toString otelAgent.localOtlpPort}" else null;
      defaultText = lib.literalExpression ''"http://127.0.0.1:''${otel.agent.localOtlpPort}" when the otel agent is enabled, else null'';
      example = "http://127.0.0.1:4319";
      description = ''
        gRPC OTLP endpoint nativelink pushes metrics/traces to (sets
        NL_OTEL_ENDPOINT). Defaults to the host-local otel agent's OTLP receiver.
        Set to null to disable OTLP export entirely.
      '';
    };

    publicListen = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:50051";

      description = "Public gRPC API (CAS/AC/Execution/ByteStream) listen address.";
    };

    trustedInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "tailscale0" ];

      description = "Interfaces on which openFirewall opens the RE ports. Defaults to tailscale0 (tailnet-only).";
    };

    # ── TLS termination at the public listener ────────────────────────────────

    tls = {
      enable = lib.mkEnableOption "TLS on the public gRPC listener (clients use grpcs://, tls=true)";

      certFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/nativelink-tls/cert.pem";

        description = "Path to the TLS certificate (PEM). Provisioned by tls.tailscale, or supply your own.";
      };

      keyFile = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/nativelink-tls/key.pem";

        description = "Path to the TLS private key (PEM).";
      };

      tailscale = {
        enable = lib.mkEnableOption "provision+renew the cert via `tailscale cert` for the node's MagicDNS name";

        domain = lib.mkOption {
          type = lib.types.str;
          example = "ultraviolence.example.ts.net";

          description = "MagicDNS name to issue the cert for (must be this node's name; tailnet HTTPS must be enabled).";
        };
      };
    };

    workerApiListen = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:50061";

      description = "Private worker_api listen address (scheduler/monolithic roles).";
    };

    workerApiEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "grpc://127.0.0.1:50061";
      example = "grpc://weyl.example.ts.net:50061";

      description = "Where a `worker` role dials the scheduler. Point this at the monolithic/scheduler host over the tailnet.";
    };

    maxStoreBytes = lib.mkOption {
      type = lib.types.int;
      default = 53687091200; # 50 GiB
      description = "Max bytes for the local-only CAS filesystem store before eviction (used when r2.enable = false).";
    };

    # ── Worker platform properties (the toolchain/RE matching handshake) ───────
    # The scheduler matches an action's requested platform properties against
    # what each worker ADVERTISES here. A Buck2/Bazel action that requests
    # properties the worker doesn't advertise will never schedule; an action
    # that requests nothing runs on whatever worker matches the defaults. For
    # REAL hermeticity the toolchain itself must be content-addressed (Nix
    # store) — these properties only route actions to capable workers, they do
    # not make a non-hermetic toolchain reproducible. See the docs note in the
    # module header / configurations comment.
    workerProperties = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);

      default = {
        cpu_count = [ "1" ];
        memory_kb = [ "1000000" ];
        # cpu_arch / OSFamily / container-image / lre-rs / ISA filled below from
        # the host; merged with whatever the host overrides here.
      };

      description = ''
        Platform properties this worker advertises to the scheduler. Keys must
        be a subset of the scheduler's supported_platform_properties. cpu_arch,
        OSFamily, container-image, lre-rs and ISA are set automatically from the
        host; override/extend here (e.g. cpu_count, memory_kb, gpu_model).
      '';
    };

    workerEntrypoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;

      description = ''
        Path to a wrapper script the worker runs every action command through
        ("entrypoint script arg..."). When null, a built-in wrapper that puts a
        baseline nix-pinned toolchain (coreutils/bash/findutils/sed/grep/awk) on
        PATH is used — required because remote actions run with NO inherited
        PATH and otherwise fail on bare `mkdir`/`sh` in the prelude scaffolding.
        Override to point at your own LRE toolchain wrapper.
      '';
    };

    # ── Local fast-cache sizing (fronting R2 when r2.enable) ──────────────────

    localCacheBytes = lib.mkOption {
      type = lib.types.int;
      default = 274877906944; # 256 GiB

      description = ''
        Size of the local NVMe filesystem fast tier that fronts R2 (per content
        store). Default 256 GiB; override down on space-constrained hosts.
      '';
    };

    memoryCacheBytes = lib.mkOption {
      type = lib.types.int;
      default = 34359738368; # 32 GiB
      description = ''
        Size of the in-memory index/hot tier fronting R2. Default 32 GiB;
        override down on memory-constrained hosts.
      '';
    };

    # ── R2 (S3-compatible) backing store ──────────────────────────────────────

    # When enabled, the CAS (dedup index + content) and AC stores become
    # fast_slow: a local filesystem/memory fast tier in front of R2 as the
    # durable slow tier. Credentials are read from `r2.environmentFile` via
    # shellexpand (${R2_ACCESS_KEY_ID}/${R2_SECRET_ACCESS_KEY}) so they never
    # enter the nix store; account_id/bucket are not secret.
    r2 = {
      enable = lib.mkEnableOption "back the CAS/AC stores with Cloudflare R2 (local fast tier + R2 slow tier)";

      accountId = lib.mkOption {
        type = lib.types.str;

        default = "";
        example = "6063b6652178f5cf1cfb87e7e41acf1e";

        description = "Cloudflare account ID (endpoint derives from it).";
      };

      bucket = lib.mkOption {
        type = lib.types.str;

        default = "";
        example = "straylight-nativelink-cas";

        description = "R2 bucket for the CAS/AC backend. nativelink namespaces within it via key_prefix.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;

        default = null;
        example = "/run/agenix/nativelink-r2-env";

        description = ''
          Env file defining R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY, fed to the
          service and referenced by the config via shellexpand. NEVER a store path.
        '';
      };
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;

      default = null;

      description = "Override the generated JSON5 config with your own file.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;

      default = false;

      description = "Open the public/worker_api ports in the firewall (if enabled).";
    };

    # ── Nix binary cache (substituter) ─────────────────────────────────────────
    # An independent nativelink instance serving the Nix HTTP binary-cache
    # protocol (nix_cache) from the straylight fork. Enable per-host; it runs
    # alongside the RE service (`enable`) and attic. Off by default.
    nixCache = {
      enable = lib.mkEnableOption "NativeLink Nix binary-cache substituter (off by default)";

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;

        defaultText = lib.literalExpression "inputs.nativelink-nix.packages.\${system}.nativelink";

        description = "Package providing the nix_cache-capable nativelink binary. Defaults to the straylight fork input.";
      };

      listen = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0:50071";

        description = "Nix binary-cache HTTP listen address. Cache root is http://<host>:<port>/nix/<instanceName>. Bound on all interfaces; exposure is gated at the firewall (trustedInterfaces).";
      };

      instanceName = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Mount instance; the cache root path is /nix/<instanceName>.";
      };

      stateDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/nativelink-nix-cache";

        description = "Directory holding the NAR / path-info / alias filesystem stores.";
      };

      storeDir = lib.mkOption {
        type = lib.types.str;
        default = "/nix/store";
        description = "StoreDir served in nix-cache-info; must match clients' store dir.";
      };

      priority = lib.mkOption {
        type = lib.types.int;
        default = 40;
        description = "Substituter priority served in nix-cache-info (lower = tried earlier).";
      };

      maxNarBytes = lib.mkOption {
        type = lib.types.int;
        default = 214748364800; # 200 GiB

        description = ''
          Total EVICTION cap for the NAR filesystem store (how much the CAS
          holds before evicting oldest). This is store capacity, not a
          per-upload limit — see maxNarUploadBytes for that. Raise on a
          dedicated builder that caches large toolchains.
        '';
      };

      maxNarUploadBytes = lib.mkOption {
        type = lib.types.int;
        default = 34359738368; # 32 GiB (the fork's own default)

        description = ''
          Per-upload cap: an upload whose UNCOMPRESSED NAR exceeds this is
          rejected with HTTP 413. It also bounds the spool when decompressing a
          compressed upload, so it doubles as a decompression-bomb guard — which
          is why the default is a conservative 32 GiB. Raise it (well under
          maxNarBytes) to accept genuinely large artifacts. Note: `-g3` debug
          builds produce enormous NARs (60-70+ GiB per output) that need this
          raised; the more durable fix is to shrink those artifacts (`-g`,
          separateDebugInfo, stripping).
        '';
      };

      signingKeyFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;

        default = null;
        example = "/run/agenix/nativelink-nix-cache-key";

        description = ''
          Path to a `nix key generate-secret` secret key. When set, the server
          signs every narinfo with it and clients trust the matching public key.
          When null, narinfos are UNSIGNED — pullers then need require-sigs =
          false (fine for a tailnet-internal workout cache). Provide via agenix;
          NEVER a store path.
        '';
      };

      trustedInterfaces = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "tailscale0" ];

        description = "Interfaces on which openFirewall opens the cache port. Tailnet-only by default.";
      };

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;

        description = "Open the cache listen port, but only on trustedInterfaces (tailscale0 by default).";
      };

      pushLocalBuilds = lib.mkOption {
        type = lib.types.bool;
        default = false;

        description = ''
          Install a nix post-build-hook that copies every locally-built path into
          this cache over loopback — populating it from this host's own builds
          (the intended workout). The hook runs synchronously after each build,
          but over loopback it is fast and is made non-fatal, so a cache hiccup
          never fails a build.
        '';
      };

      pushCompression = lib.mkOption {
        type = lib.types.enum [
          "zstd"
          "xz"
          "none"
        ];

        default = "zstd";
        description = ''
          Compression `nix copy` applies when pushLocalBuilds pushes a path.
          `nix copy`'s own compression is the throughput bottleneck, not the
          cache: xz (nix's default) is CPU-bound to a crawl on large NARs
          (hours on tens-of-GiB toolchains), while zstd sustains hundreds of
          MB/s at a fraction of the CPU. `none` is fastest on a fast loopback/
          LAN link. The server stores + serves back whatever compression was
          pushed (round-trip fidelity), so this is a pure push-cost choice.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # nativelink's local store is a reconstructible CAS: content is R2-backed or
      # re-derivable, so it's persisted across an impermanence reboot (warm cache)
      # but NOT backed up to R2 — paying to back up re-creatable CAS is waste.
      hyper-modern-nixos.state.dirs.nativelink = {
        path = storeRoot;
        class = "reconstructible";
      };

      assertions = [
        {
          assertion = cfg.role != "worker" || cfg.workerApiEndpoint != "grpc://127.0.0.1:50061";
          message = "nativelink role=worker but workerApiEndpoint still points at localhost. Set it to the scheduler host's worker_api over the tailnet.";
        }
        {
          assertion =
            !cfg.r2.enable || (cfg.r2.accountId != "" && cfg.r2.bucket != "" && cfg.r2.environmentFile != null);
          message = ''
            hyper-modern-nixos.nativelink.r2.enable is true but accountId/bucket/
            environmentFile are not all set. Provide r2.accountId, r2.bucket, and
            r2.environmentFile (with R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY).
          '';
        }
        {
          assertion = !cfg.tls.tailscale.enable || cfg.tls.tailscale.domain != "";
          message = "nativelink.tls.tailscale.enable is true but tls.tailscale.domain (the node's MagicDNS name) is unset.";
        }
      ];

      # Provision + renew the listener cert via `tailscale cert`. Writes to the
      # configured cert/key paths (root:nativelink-readable), and a daily timer
      # refreshes before the 90-day Let's Encrypt expiry. nativelink waits on it.
      systemd.services.nativelink-tls-cert = lib.mkIf cfg.tls.tailscale.enable {
        description = "Provision nativelink TLS cert via tailscale (${cfg.tls.tailscale.domain})";
        after = [ "tailscaled.service" ];
        wants = [ "tailscaled.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -euo pipefail
          certdir="$(dirname ${lib.escapeShellArg cfg.tls.certFile})"
          ${pkgs.coreutils}/bin/mkdir -p "$certdir"
          # Retry until tailscale DNS/cert provisioning is ready.
          for i in $(seq 1 30); do
            if ${config.services.tailscale.package}/bin/tailscale cert \
                 --cert-file ${lib.escapeShellArg cfg.tls.certFile} \
                 --key-file ${lib.escapeShellArg cfg.tls.keyFile} \
                 ${lib.escapeShellArg cfg.tls.tailscale.domain}; then
              break
            fi
            echo "tailscale cert not ready yet ($i/30), retrying in 10s..."
            ${pkgs.coreutils}/bin/sleep 10
          done
          # nativelink runs as DynamicUser=no/root here, so root-readable is fine;
          # widen if you later run nativelink as a dedicated user.
          ${pkgs.coreutils}/bin/chmod 0640 ${lib.escapeShellArg cfg.tls.keyFile}
        '';
      };

      systemd.timers.nativelink-tls-cert = lib.mkIf cfg.tls.tailscale.enable {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };

      systemd.services.nativelink = {
        description = "NativeLink remote execution (${cfg.role})";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
        ]
        ++ lib.optional cfg.tls.tailscale.enable "nativelink-tls-cert.service";
        wants = [
          "network-online.target"
        ]
        ++ lib.optional cfg.tls.tailscale.enable "nativelink-tls-cert.service";
        # OTLP push target (metrics + traces). Empty list when otlpEndpoint is
        # null, so export stays off unless a collector is wired up.
        environment = lib.optionalAttrs (cfg.otlpEndpoint != null) {
          NL_OTEL_ENDPOINT = cfg.otlpEndpoint;
        };
        serviceConfig = {
          ExecStart = "${nativelinkPkg}/bin/nativelink ${configFile}";
          Restart = "on-failure";
          RestartSec = 5;
          StateDirectory = "nativelink";
          # R2 creds for shellexpand in the config (${R2_ACCESS_KEY_ID} etc.).
          EnvironmentFile = lib.mkIf (cfg.r2.enable && cfg.r2.environmentFile != null) cfg.r2.environmentFile;
          # Workers exec arbitrary build actions in work_directory, so we cannot
          # apply the strict sandbox we'd use for a pure cache. Keep it modest.
          NoNewPrivileges = lib.mkDefault (cfg.role == "scheduler");
        };
      };

      systemd.tmpfiles.rules = [ "d ${storeRoot} 0750 root root - -" ];

      # Open the public + worker_api ports, but ONLY on the trusted (tailscale)
      # interfaces — the RE endpoint is tailnet-reachable, never internet-exposed,
      # even though publicListen binds all interfaces.
      networking.firewall = lib.mkIf cfg.openFirewall (
        let
          # dhallHost: the typed fleet uses fixed ports — public 50051, CAS 50052,
          # worker_api 50061. Open all three on the trusted interfaces (every node
          # runs a CAS server the shard ring grpc's to; the scheduler also serves
          # public + worker_api). Legacy path opens publicListen + workerApiListen.
          ports =
            if cfg.dhallHost != null then
              [
                50051
                50052
                50061
              ]
            else
              [
                (lib.toInt (lib.last (lib.splitString ":" cfg.publicListen)))
                (lib.toInt (lib.last (lib.splitString ":" cfg.workerApiListen)))
              ];
        in
        {
          interfaces = lib.genAttrs cfg.trustedInterfaces (_: {
            allowedTCPPorts = ports;
          });
        }
      );
    })

    # ── Nix binary-cache substituter (independent of the RE service above) ──────

    (lib.mkIf cfg.nixCache.enable {
      # A reconstructible cache: NARs are re-pushable/re-derivable, so the store
      # is persisted across an impermanence reboot (warm cache) but not backed up.
      hyper-modern-nixos.state.dirs.nativelink-nix-cache = {
        path = cfg.nixCache.stateDir;
        class = "reconstructible";
      };

      systemd.tmpfiles.rules = [ "d ${cfg.nixCache.stateDir} 0750 root root - -" ];

      systemd.services.nativelink-nix-cache = {
        description = "NativeLink Nix binary-cache substituter";

        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          ExecStart = "${nixCachePkg}/bin/nativelink ${nixCacheConfigFile}";
          Restart = "on-failure";
          RestartSec = 5;
          StateDirectory = "nativelink-nix-cache";
        };
      };

      # Open the cache port only on the trusted (tailscale) interfaces.
      networking.firewall = lib.mkIf cfg.nixCache.openFirewall {
        interfaces = lib.genAttrs cfg.nixCache.trustedInterfaces (_: {
          allowedTCPPorts = [ (lib.toInt nixCachePort) ];
        });
      };

      # Populate the cache from this host's own builds (the workout). Non-fatal:
      # a cache hiccup logs and returns 0 so it never fails a build.
      nix.settings.post-build-hook = lib.mkIf cfg.nixCache.pushLocalBuilds (
        toString (
          pkgs.writeShellScript "nativelink-nix-cache-push" ''
            set -u
            [ -n "''${OUT_PATHS:-}" ] || exit 0
            ${config.nix.package}/bin/nix copy --to \
              'http://127.0.0.1:${nixCachePort}/nix/${cfg.nixCache.instanceName}?compression=${cfg.nixCache.pushCompression}' $OUT_PATHS \
              || echo "nativelink-nix-cache: push failed (non-fatal)" >&2
          ''
        )
      );
    })
  ];
}
