# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                          // hyper-modern-nixos // nativelink
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
#   - role = "monolithic" on an x86_64 host (e.g. weyl/noether): CAS + scheduler
#     + an x86_64 worker. Exposes the public API (50051) and worker_api (50061).
#   - role = "worker"     on shimmer (aarch64 DGX): an aarch64-only worker that
#     dials the monolithic host's worker_api over the tailnet.
#
# ── THE TOOLCHAIN PROBLEM (read this before expecting remote EXECUTION) ──────
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

  cpuArch = if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64" else "x86_64";

  # JSON5 is a superset of JSON, and nativelink accepts JSON, so we can generate
  # the config with the plain JSON writer.
  jsonFormat = pkgs.formats.json { };

  # ── Store / scheduler / worker fragments ─────────────────────────────────────
  # NativeLink 1.5.x config schema: `stores` and `schedulers` are ARRAYS of
  # named objects ({ name = "..."; <backend> = {...}; }), NOT maps keyed by
  # name (the pre-1.x form). `workers` was always an array. Getting this wrong
  # yields `invalid type: map, expected a sequence` at startup.
  storeRoot = "/var/lib/nativelink";

  # R2 slow-tier fragment. account_id/bucket are non-secret; creds come from the
  # service environment via shellexpand so they never land in the store.
  r2Backend = keyPrefix: {
    experimental_cloud_object_store = {
      provider = "r2";
      account_id = cfg.r2.accountId;
      bucket = cfg.r2.bucket;
      access_key_id = "\${R2_ACCESS_KEY_ID}";
      secret_access_key = "\${R2_SECRET_ACCESS_KEY}";
      key_prefix = keyPrefix;
      retry = {
        max_retries = 6;
        delay = 0.3;
        jitter = 0.5;
      };
    };
  };

  # ── Local-only stores (r2.enable = false) ────────────────────────────────────
  localCasStores = [
    {
      name = "CAS_MAIN_STORE";
      filesystem = {
        content_path = "${storeRoot}/content";
        temp_path = "${storeRoot}/tmp";
        eviction_policy.max_bytes = cfg.maxStoreBytes;
      };
    }
    {
      name = "AC_MAIN_STORE";
      filesystem = {
        content_path = "${storeRoot}/ac-content";
        temp_path = "${storeRoot}/ac-tmp";
        eviction_policy.max_bytes = 67108864; # 64 MiB
      };
    }
    {
      name = "WORKER_FAST_SLOW_STORE";
      fast_slow = {
        fast.filesystem = {
          content_path = "${storeRoot}/worker-content";
          temp_path = "${storeRoot}/worker-tmp";
          eviction_policy.max_bytes = cfg.maxStoreBytes;
        };
        fast_direction = "get";
        slow.ref_store.name = "CAS_MAIN_STORE";
      };
    }
  ];

  # ── R2-backed stores (r2.enable = true) ──────────────────────────────────────
  # CAS = verify → dedup → { index_store, content_store }, each a fast_slow with
  # a local fast tier (NVMe filesystem for content, memory for the index) in
  # front of R2. AC = fast_slow (memory fast tier + R2). This mirrors the
  # upstream r2_backend.json5 example but uses a disk fast tier for content so
  # the local NVMe cache is durable across restarts.
  r2CasStores = [
    {
      name = "CAS_MAIN_STORE";
      verify = {
        verify_size = true;
        backend.dedup = {
          index_store.fast_slow = {
            fast.memory.eviction_policy.max_bytes = cfg.memoryCacheBytes;
            fast_direction = "get";
            slow = r2Backend "cas-index/";
          };
          content_store.compression = {
            compression_algorithm.lz4 = { };
            backend.fast_slow = {
              fast.filesystem = {
                content_path = "${storeRoot}/content";
                temp_path = "${storeRoot}/tmp";
                eviction_policy.max_bytes = cfg.localCacheBytes;
              };
              fast_direction = "get";
              slow = r2Backend "cas/";
            };
          };
        };
      };
    }
    {
      name = "AC_MAIN_STORE";
      fast_slow = {
        fast.memory.eviction_policy.max_bytes = 67108864; # 64 MiB hot AC
        fast_direction = "get";
        slow = r2Backend "ac/";
      };
    }
    # LocalWorker still needs a fast_slow store; front the same local NVMe tier
    # with a ref to the (R2-backed) CAS as the slow side.
    {
      name = "WORKER_FAST_SLOW_STORE";
      fast_slow = {
        fast.filesystem = {
          content_path = "${storeRoot}/worker-content";
          temp_path = "${storeRoot}/worker-tmp";
          eviction_policy.max_bytes = cfg.localCacheBytes;
        };
        fast_direction = "get";
        slow.ref_store.name = "CAS_MAIN_STORE";
      };
    }
  ];

  casStores = if cfg.r2.enable then r2CasStores else localCasStores;

  inst = cfg.instanceName;

  # The full canonical RE property set Buck2/Bazel negotiate over, with the
  # match modes from the upstream buck2_cas.json5. The scheduler must SUPPORT a
  # superset of what any worker advertises and what any action requests.
  schedulerFragment = [
    {
      name = "MAIN_SCHEDULER";
      simple.supported_platform_properties = {
        cpu_count = "minimum";
        memory_kb = "minimum";
        network_kbps = "minimum";
        disk_read_iops = "minimum";
        disk_read_bps = "minimum";
        disk_write_iops = "minimum";
        disk_write_bps = "minimum";
        shm_size = "minimum";
        gpu_count = "minimum";
        gpu_model = "exact";
        cpu_vendor = "exact";
        cpu_arch = "exact";
        cpu_model = "exact";
        kernel_version = "exact";
        OSFamily = "priority";
        "container-image" = "priority";
        "lre-rs" = "priority";
        ISA = "exact";
      };
    }
  ];

  publicServer = {
    name = "public";
    listener.http.socket_address = cfg.publicListen;
    services = {
      cas = [
        {
          instance_name = inst;
          cas_store = "CAS_MAIN_STORE";
        }
      ];
      ac = [
        {
          instance_name = inst;
          ac_store = "AC_MAIN_STORE";
        }
      ];
      execution = [
        {
          instance_name = inst;
          cas_store = "CAS_MAIN_STORE";
          scheduler = "MAIN_SCHEDULER";
        }
      ];
      bytestream = [
        {
          instance_name = inst;
          cas_store = "CAS_MAIN_STORE";
        }
      ];
      capabilities = [
        {
          instance_name = inst;
          remote_execution.scheduler = "MAIN_SCHEDULER";
        }
      ];
    };
  };

  workerApiServer = {
    name = "private_workers_servers";
    listener.http.socket_address = cfg.workerApiListen;
    services = {
      worker_api.scheduler = "MAIN_SCHEDULER";
      admin = { };
      health = { };
    };
  };

  # Worker-advertised properties: host-derived arch/OS/ISA + container-image and
  # lre-rs left empty (the "priority" match makes empty = "no preference"), and
  # whatever the host set in cfg.workerProperties (cpu_count, memory_kb, …).
  workerPlatformProperties = (lib.mapAttrs (_: values: { inherit values; }) cfg.workerProperties) // {
    cpu_arch.values = [ cpuArch ];
    OSFamily.values = [ "" ];
    "container-image".values = [ "" ];
    "lre-rs".values = [ "" ];
    ISA.values = [ (if pkgs.stdenv.hostPlatform.isAarch64 then "aarch64" else "x86-64") ];
  };

  # Per-action entrypoint wrapper. Remote actions run in a sandbox with NO
  # inherited PATH, so even the prelude's own scaffolding (`mkdir`, `cd`, the
  # shell) fails with "command not found". This wrapper prepends a baseline,
  # nix-pinned toolchain to PATH before exec'ing the action's command, which is
  # the minimum to make non-LRE genrule/sh actions run remotely. It is NOT full
  # hermeticity (the action can still reach other store paths it names) — for
  # real reproducibility the client should pin its whole toolchain — but it
  # makes the worker behave like a sane *nix box. Content-addressed, so it's
  # itself a stable input. Override via cfg.workerEntrypoint.
  defaultEntrypoint = pkgs.writeShellScript "nativelink-entrypoint" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.bash
        pkgs.findutils
        pkgs.gnused
        pkgs.gnugrep
        pkgs.gawk
      ]
    }:$PATH"
    exec "$@"
  '';

  entrypoint = if cfg.workerEntrypoint != null then cfg.workerEntrypoint else "${defaultEntrypoint}";

  localWorker = {
    local = {
      worker_api_endpoint.uri = cfg.workerApiEndpoint;
      inherit entrypoint;
      cas_fast_slow_store = "WORKER_FAST_SLOW_STORE";
      upload_action_result.ac_store = "AC_MAIN_STORE";
      work_directory = "${storeRoot}/work";
      platform_properties = workerPlatformProperties;
    };
  };

  # role -> assembled config
  configFor =
    role:
    {
      stores = casStores;
      global.max_open_files = 24576;
    }
    // lib.optionalAttrs (role == "monolithic" || role == "scheduler") {
      schedulers = schedulerFragment;
      servers = [
        publicServer
        workerApiServer
      ];
    }
    // lib.optionalAttrs (role == "monolithic" || role == "worker") { workers = [ localWorker ]; };

  configFile =
    if cfg.configFile != null then
      cfg.configFile
    else
      jsonFormat.generate "nativelink.json" (configFor cfg.role);
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
      '';
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

    publicListen = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:50051";
      description = "Public gRPC API (CAS/AC/Execution/ByteStream) listen address.";
    };

    workerApiListen = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0:50061";
      description = "Private worker_api listen address (scheduler/monolithic roles).";
    };

    workerApiEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "grpc://127.0.0.1:50061";
      example = "grpc://weyl.risk-nunki.ts.net:50061";
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
  };

  config = lib.mkIf cfg.enable {
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
    ];

    systemd.services.nativelink = {
      description = "NativeLink remote execution (${cfg.role})";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
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

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [
        (lib.toInt (lib.last (lib.splitString ":" cfg.publicListen)))
        (lib.toInt (lib.last (lib.splitString ":" cfg.workerApiListen)))
      ];
    };
  };
}
