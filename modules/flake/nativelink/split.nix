# One systemd unit per NativeLink process, for a host whose Dhall layout is
# `split` (data/fleet.dhall `processesFor`, rendered by
# data/render-processes.dhall). The fork's module runs ONE nativelink.service
# per host; this keeps that module (binary, worker entrypoint, firewall,
# tmpfiles, state dir, the version pin) and swaps its unit for
# nativelink-{scheduler,cas,worker}.service under nativelink.target.
#
# Everything a process runs with is taken FROM the fork's unit, not restated:
# the binary is the prefix of its ExecStart (asserted, so a version bump moves
# both), the worker entrypoint is read out of its rendered monolithic config,
# and its serviceConfig is copied whole. The build also proves the processes
# PARTITION that monolithic config (./partition.jq), so the split cannot drift
# from the topology the fork's module would have run.
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.hyper-modern-nixos.nativelink;
  sp = cfg.split;
  fork = config.systemd.services.nativelink;
  otelAgent = config.hyper-modern-nixos.observability.otel.agent;
  buildPkgs = pkgs.buildPackages;

  nativelinkPkg =
    if cfg.package != null then
      cfg.package
    else
      flake.inputs.nativelink-nix.packages.${pkgs.stdenv.hostPlatform.system}.nativelink;
  bin = "${nativelinkPkg}/bin/nativelink";

  # The fork's rendered monolithic config: its ExecStart is "<bin> <config>".
  forkConfig = lib.removePrefix "${bin} " fork.serviceConfig.ExecStart;

  # Content-address just the Dhall (as the fork's module does), so unrelated
  # commits don't give every process config a new store path.
  fleetDir = builtins.path {
    path = cfg.fleetDir;
    name = "nativelink-fleet";
  };

  rendered =
    buildPkgs.runCommand "nativelink-${cfg.dhallHost}-processes"
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
        export XDG_CACHE_HOME="$TMPDIR/dhall-cache" HOME="$TMPDIR"
        mkdir -p "$XDG_CACHE_HOME" "$out"
        host=${lib.escapeShellArg cfg.dhallHost}
        dhall-to-json --file ${fleetDir}/render-processes.dhall > rows.json

        # The Dhall decides the processes; these units were declared for exactly
        # these, in this order.
        have=$(jq -r --arg h "$host" '[.[] | select(.host == $h) | .process] | join(" ")' rows.json)
        if [ "$have" != ${lib.escapeShellArg (lib.concatStringsSep " " sp.processes)} ]; then
          echo "nativelink split: Dhall renders '$have' for $host, units declare '${lib.concatStringsSep " " sp.processes}'" >&2
          exit 1
        fi

        # The worker runs whatever entrypoint the fork's module put in its own
        # render (the floor wrapper, or workerEntrypoint): same walk, same value.
        ep=$(jq -er '[.. | objects | select((.local | type) == "object") | .local.entrypoint] | first' ${forkConfig})
        for p in $have; do
          jq -r --arg h "$host" --arg p "$p" '.[] | select(.host == $h and .process == $p) | .json' rows.json \
            | jq --arg ep "$ep" '
                walk(
                  if type == "object"
                     and (.local | type) == "object"
                     and (.local | has("work_directory"))
                  then .local += { entrypoint: $ep }
                  else . end
                )' > "$out/$p.json"
        done

        verdict=$(jq --slurpfile parts <(cat "$out"/*.json) -f ${./partition.jq} ${forkConfig})
        if [ "$(jq -r .ok <<< "$verdict")" != true ]; then
          echo "nativelink split: processes do not partition the monolithic config:" >&2
          jq .why <<< "$verdict" >&2
          exit 1
        fi
      '';

  # What each process waits for. The scheduler's CAS stores and the worker's
  # fast_slow both dial :50052; the worker also dials the worker API.
  deps = {
    scheduler = [ "nativelink-cas.service" ];
    cas = [ ];
    worker = [
      "nativelink-cas.service"
    ]
    ++ lib.optional (lib.elem "scheduler" sp.processes) "nativelink-scheduler.service";
  };

  # Per-process OTLP receivers on the local agent: all nativelink.role=re (so
  # the dashboards keyed on it still see the RE service), plus which process.
  otlpPort = {
    scheduler = 4321;
    cas = 4323;
    worker = 4324;
  };

  unitFor = p: {
    description = "NativeLink ${p} (split: fleet.dhall processesFor)";
    wantedBy = [ "nativelink.target" ];
    partOf = [ "nativelink.target" ];
    after = fork.after ++ deps.${p};
    wants = fork.wants ++ deps.${p};
    inherit (fork) path;
    environment =
      removeAttrs fork.environment [ "PATH" ]
      // lib.optionalAttrs otelAgent.enable {
        NL_OTEL_ENDPOINT = "http://127.0.0.1:${toString otlpPort.${p}}";
      };
    serviceConfig =
      removeAttrs fork.serviceConfig [
        "ExecStart"
        "EnvironmentFile"
      ]
      // {
        ExecStart = "${bin} ${rendered}/${p}.json";
      }
      # Only the CAS reaches the slow tier, so only it gets the credentials.
      // lib.optionalAttrs (p == "cas" && fork.serviceConfig ? EnvironmentFile) {
        inherit (fork.serviceConfig) EnvironmentFile;
      };
  };
in
{
  options.hyper-modern-nixos.nativelink.split = {
    enable = lib.mkEnableOption "one unit per NativeLink process (the host's Dhall layout must be `split`)";
    processes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "scheduler"
          "cas"
          "worker"
        ]
      );
      default = [
        "scheduler"
        "cas"
        "worker"
      ];
      description = ''
        The processes fleet.dhall `processesFor` renders for this host, in its
        order. Checked against the render at build time; drop "scheduler" on a
        split host whose site schedules elsewhere.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && sp.enable) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.dhallHost != null;
            message = "hyper-modern-nixos.nativelink.split needs dhallHost (the processes come from the Dhall fleet).";
          }
          {
            assertion = forkConfig != fork.serviceConfig.ExecStart;
            message = "hyper-modern-nixos.nativelink.split: the fork's ExecStart no longer starts with ${bin}; the split would run a different binary.";
          }
        ];

        # Masked, and out of multi-user.target.wants (enable = false alone keeps
        # the wants link, which would ask systemd to start a masked unit).
        systemd.services = {
          nativelink = {
            enable = false;
            wantedBy = lib.mkForce [ ];
          };
        }
        // lib.listToAttrs (map (p: lib.nameValuePair "nativelink-${p}" (unitFor p)) sp.processes);

        systemd.targets.nativelink = {
          description = "NativeLink remote execution (split)";
          wantedBy = [ "multi-user.target" ];
        };
      }
      (lib.mkIf otelAgent.enable {
        hyper-modern-nixos.observability.otel.agent.taggedOtlp =
          lib.optionalAttrs (lib.elem "scheduler" sp.processes) {
            nativelink-re.attributes."nativelink.process" = "scheduler";
          }
          // lib.listToAttrs (
            map (
              p:
              lib.nameValuePair "nativelink-re-${p}" {
                port = otlpPort.${p};
                attributes = {
                  "nativelink.role" = "re";
                  "nativelink.process" = p;
                  "deployment.environment" = "fleet";
                };
              }
            ) (lib.remove "scheduler" sp.processes)
          );
      })
    ]
  );
}
