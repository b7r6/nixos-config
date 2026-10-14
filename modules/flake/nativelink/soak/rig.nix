# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                       // hypermodern // nativelink // soak rig
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The soak driver for a NativeLink site (docs/azure-soak-fleet.md). One `soak`
# CLI + a oneshot unit that runs a whole chaos campaign against the site's
# scheduler over the tailnet, in the shape of rechaos-nativelink-raft/run.sh:
#
#   1. gateway  rechaos serve in front of the scheduler, seeded fault policy,
#               recording a replayable timeline
#   2. clean    deterministic REAPI build through the gateway -> trees/clean
#   3. monkey   rechaos chaos-monkey.py --execution --soak, one slice per seed,
#               direct to the scheduler, scraping its /metrics for the
#               rising-floor (leak) detector; meanwhile a seeded kill loop
#               SIGKILLs the scheduler's nativelink over ssh (process chaos —
#               rechaos's process_chaos.py is local-only by design)
#   4. stress   scheduler-focused workload through the faulting gateway
#   5. verify   the same deterministic build again -> trees/chaos, then
#               `rechaos oracle trees/clean trees/chaos`
#   6. collect  every finding source -> findings/all.jsonl + summary.json
#
# Everything the run needs is in the closure: rechaos (flake input, pinned by
# rev — the manifest records it), its Python (grpcio + generated protos), the
# vendored workload/collector. Nothing is fetched at run time.
#
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.hyper-modern-nixos.soakRig;
  system = pkgs.stdenv.hostPlatform.system;

  rechaosSrc = flake.inputs.rechaos;
  rechaos = rechaosSrc.packages.${system}.default;
  rechaosRev = rechaosSrc.rev or rechaosSrc.shortRev or "dirty";

  py = pkgs.python3.withPackages (p: [
    p.grpcio
    p.grpcio-tools
    p.protobuf
  ]);

  # The chaos monkey and the workload import rechaos's generated protos
  # (build.bazel.remote.execution.v2, google.bytestream, …); the harness
  # generated them into $RECHAOS_DIR/.build/python with this exact line.
  protos = pkgs.runCommand "rechaos-python-protos" { nativeBuildInputs = [ py ]; } ''
    mkdir -p "$out"
    cd ${rechaosSrc}
    find proto -name '*.proto' -print0 \
      | xargs -0 python3 -m grpc_tools.protoc -Iproto --python_out="$out" --grpc_python_out="$out"
  '';

  soak = pkgs.writeShellApplication {
    name = "soak";
    runtimeInputs = [
      py
      rechaos
      pkgs.openssh
      pkgs.coreutils
      pkgs.gawk
      pkgs.jq
      pkgs.curl
    ];
    text = ''
      # soak — one chaos/soak campaign against a NativeLink site, from the rig.
      #
      #   soak run [DURATION_S]      the whole campaign (default $SOAK_DURATION_S)
      #   soak build [SALT]          one deterministic build through a fresh gateway
      #   soak kill                  SIGKILL the scheduler's nativelink once
      #   soak status                target reachability + worker count
      #
      # Knobs are SOAK_* env vars; the unit reads /etc/soak/env. Runs land in
      # $SOAK_RUNS_DIR/<utc>/ (manifest, summary, findings, timelines, trees).
      : "''${SOAK_TARGET_HOST:=${cfg.targetHost}}"
      : "''${SOAK_TARGET_PORT:=${toString cfg.targetPort}}"
      : "''${SOAK_GW_PORT:=50070}"
      : "''${SOAK_DURATION_S:=${toString cfg.durationSeconds}}"
      : "''${SOAK_SEEDS:=${lib.concatStringsSep " " (map toString cfg.seeds)}}"
      : "''${SOAK_MONKEY_SHARE:=60}"
      : "''${SOAK_DRAIN_S:=45}"
      : "''${SOAK_KILL_EVERY_S:=${toString cfg.killEverySeconds}}"
      : "''${SOAK_KILL_JITTER_S:=${toString cfg.killJitterSeconds}}"
      : "''${SOAK_RUNS_DIR:=/var/lib/soak/runs}"
      : "''${SOAK_SSH_KEY:=/var/lib/soak/id_ed25519}"
      : "''${SOAK_POLICY:=${./gateway-workload.json}}"
      : "''${SOAK_WORKERS:=${toString cfg.expectedWorkers}}"
      export PYTHONPATH="${protos}" PYTHONDONTWRITEBYTECODE=1 RECHAOS_BIN="${rechaos}/bin/rechaos"

      MONKEY="${rechaosSrc}/scripts/chaos-monkey.py"
      WORKLOAD="${./reapi_workload.py}"
      COLLECT="${./collect.py}"
      TARGET="$SOAK_TARGET_HOST:$SOAK_TARGET_PORT"

      log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
      die() { log "FATAL: $*"; exit 2; }

      ssh_target() {
        ssh -i "$SOAK_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10 \
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/var/lib/soak/known_hosts \
          "root@$SOAK_TARGET_HOST" "$@"
      }

      wait_port() { # HOST PORT TIMEOUT_S [PID]
        local deadline=$((SECONDS + $3))
        while (( SECONDS < deadline )); do
          if [[ -n "''${4:-}" ]] && ! kill -0 "$4" 2>/dev/null; then return 1; fi
          (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null && return 0
          sleep 0.5
        done
        return 1
      }

      GW_PID=""
      start_gateway() { # RUN_DIR [POLICY]
        local extra=()
        [[ -n "''${2:-}" ]] && extra=(--policy "$2")
        mkdir -p "$1/gateway"
        rechaos serve --upstream-host "$SOAK_TARGET_HOST" --upstream-port "$SOAK_TARGET_PORT" \
          --port "$SOAK_GW_PORT" --max-call-seconds 180 \
          --record "$1/gateway/timeline.jsonl" "''${extra[@]}" \
          >"$1/logs/gateway.log" 2>&1 &
        GW_PID=$!
        wait_port 127.0.0.1 "$SOAK_GW_PORT" 30 "$GW_PID" \
          || { tail "$1/logs/gateway.log" >&2; die "gateway failed to start"; }
        log "gateway up on :$SOAK_GW_PORT -> $TARGET (pid $GW_PID''${2:+, policy $2})"
      }
      stop_gateway() {
        [[ -n "$GW_PID" ]] || return 0
        kill -INT "$GW_PID" 2>/dev/null || true   # INT lets it flush the timeline
        wait "$GW_PID" 2>/dev/null || true
        GW_PID=""
      }

      KILLER_PID=""
      start_killer() { # RUN_DIR SEED
        (( SOAK_KILL_EVERY_S > 0 )) || return 0
        (
          RANDOM=$2
          while true; do
            jitter=$(( SOAK_KILL_JITTER_S > 0 ? (RANDOM % (2 * SOAK_KILL_JITTER_S + 1)) - SOAK_KILL_JITTER_S : 0 ))
            sleep $(( SOAK_KILL_EVERY_S + jitter ))
            ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            if ssh_target systemctl kill -s KILL nativelink.service >/dev/null 2>&1; then
              printf '{"ts":"%s","action":"kill -9 nativelink","ok":true}\n' "$ts" >>"$1/kills.jsonl"
            else
              printf '{"ts":"%s","action":"kill -9 nativelink","ok":false}\n' "$ts" >>"$1/kills.jsonl"
            fi
          done
        ) &
        KILLER_PID=$!
        log "scheduler kill loop every ~''${SOAK_KILL_EVERY_S}s ±''${SOAK_KILL_JITTER_S}s (pid $KILLER_PID)"
      }
      stop_killer() {
        [[ -n "$KILLER_PID" ]] || return 0
        kill "$KILLER_PID" 2>/dev/null || true
        wait "$KILLER_PID" 2>/dev/null || true
        KILLER_PID=""
      }

      teardown() {
        local rc=$?
        trap - EXIT INT TERM
        stop_killer
        stop_gateway
        exit "$rc"
      }

      wait_workers() { # TIMEOUT_S — until the scheduler reports >= SOAK_WORKERS registered workers
        local deadline=$((SECONDS + $1)) n
        while (( SECONDS < deadline )); do
          n=$(curl -sf "http://$TARGET/metrics" 2>/dev/null \
                | awk '/^nativelink_scheduler_workers_count[ {]/ { s += $NF } /^nativelink_scheduler_worker_count[ {]/ { s += $NF } END { print s + 0 }')
          if (( n >= SOAK_WORKERS )); then log "$n workers registered"; return 0; fi
          sleep 2
        done
        log "warning: could not confirm $SOAK_WORKERS workers via /metrics (last: ''${n:-?}); continuing"
        return 0
      }

      cmd_status() {
        if wait_port "$SOAK_TARGET_HOST" "$SOAK_TARGET_PORT" 5; then echo "target $TARGET: reachable"; else echo "target $TARGET: UNREACHABLE"; exit 1; fi
        curl -sf "http://$TARGET/metrics" | grep -E '^nativelink_scheduler_(worker|workers)_count' || echo "(no worker-count metric on /metrics)"
        ssh_target systemctl is-active nativelink.service || true
      }

      cmd_kill() { ssh_target systemctl kill -s KILL nativelink.service && echo "killed nativelink on $SOAK_TARGET_HOST"; }

      cmd_build() { # [SALT]
        local salt="''${1:-adhoc}" ts R
        ts=$(date -u +%Y%m%dT%H%M%SZ); R="$SOAK_RUNS_DIR/build-$ts"
        mkdir -p "$R/logs" "$R/workload" "$R/trees"
        trap teardown EXIT INT TERM
        start_gateway "$R"
        python3 "$WORKLOAD" build --target "127.0.0.1:$SOAK_GW_PORT" --salt "$salt" \
          --out "$R/trees/$salt" --report "$R/workload/build-$salt.json"
        log "build report: $R/workload/build-$salt.json"
      }

      cmd_run() { # [DURATION_S]
        local DURATION="''${1:-$SOAK_DURATION_S}" ts R
        ts=$(date -u +%Y%m%dT%H%M%SZ); R="$SOAK_RUNS_DIR/$ts"
        mkdir -p "$R"/{logs,findings,monkey,workload,trees}
        ln -sfn "$R" "$SOAK_RUNS_DIR/latest"
        trap teardown EXIT INT TERM

        jq -n --arg ts "$ts" --arg target "$TARGET" --arg rev "${rechaosRev}" \
           --argjson duration "$DURATION" --argjson workers "$SOAK_WORKERS" \
           --arg seeds "$SOAK_SEEDS" --argjson kill_every "$SOAK_KILL_EVERY_S" \
           '{kind:"run", backend:"memory", timestamp:$ts, target:$target, site:"az",
             rechaos_rev:$rev, rechaos_bin:"${rechaos}/bin/rechaos", harness:"nixos-config soak rig",
             workers:$workers, duration_s:$duration, seeds:$seeds, kill_every_s:$kill_every,
             ports:{target:'"$SOAK_TARGET_PORT"', gateway:'"$SOAK_GW_PORT"'}}' >"$R/manifest.json"
        log "run dir: $R"

        wait_port "$SOAK_TARGET_HOST" "$SOAK_TARGET_PORT" 60 || die "target $TARGET unreachable"
        wait_workers 120
        start_gateway "$R" "$SOAK_POLICY"
        GW="127.0.0.1:$SOAK_GW_PORT"

        log "phase 1: clean build"
        python3 "$WORKLOAD" build --target "$GW" --salt clean --out "$R/trees/clean" \
          --report "$R/workload/build-clean.json" || log "clean build reported findings"

        read -r -a seeds <<<"$SOAK_SEEDS"
        monkey_total=$((DURATION * SOAK_MONKEY_SHARE / 100))
        slice=$((monkey_total / ''${#seeds[@]}))
        (( slice < 10 )) && slice=10
        start_killer "$R" "''${seeds[0]}"
        for seed in "''${seeds[@]}"; do
          log "phase 2: chaos-monkey seed=$seed for ''${slice}s (direct to $TARGET, --execution --soak)"
          python3 "$MONKEY" \
            --host "$SOAK_TARGET_HOST" --port "$SOAK_TARGET_PORT" --metrics-port "$SOAK_TARGET_PORT" \
            --instance main --execution --soak --seed "$seed" --run-id "seed-$seed" --output "$R/monkey" \
            --minutes "$(awk "BEGIN{print $slice/60}")" --drain-seconds "$SOAK_DRAIN_S" \
            >"$R/logs/monkey-$seed.log" 2>&1 || true
          log "monkey seed=$seed exit=$? ($(tail -n1 "$R/logs/monkey-$seed.log" 2>/dev/null))"
        done
        stop_killer

        stress_s=$((DURATION - monkey_total))
        (( stress_s < 10 )) && stress_s=10
        log "phase 3: scheduler stress ''${stress_s}s through the faulting gateway"
        python3 "$WORKLOAD" stress --target "$GW" --seed "''${seeds[0]}" --seconds "$stress_s" \
          --report "$R/workload/stress.json" >"$R/logs/stress.log" 2>&1 || true
        log "stress exit=$? ($(tail -n1 "$R/logs/stress.log" 2>/dev/null))"

        log "phase 4: verify build + oracle"
        wait_workers 120
        python3 "$WORKLOAD" build --target "$GW" --salt chaos --out "$R/trees/chaos" \
          --report "$R/workload/build-chaos.json" || log "verify build reported findings"
        if [[ -d "$R/trees/clean" && -d "$R/trees/chaos" ]]; then
          rechaos oracle "$R/trees/clean" "$R/trees/chaos" >"$R/workload/oracle-clean-vs-chaos.json" 2>&1
          echo $? >"$R/workload/oracle-clean-vs-chaos.rc"
        else
          echo "missing tree" >"$R/workload/oracle-clean-vs-chaos.json"; echo 2 >"$R/workload/oracle-clean-vs-chaos.rc"
        fi
        log "oracle: rc=$(cat "$R/workload/oracle-clean-vs-chaos.rc") $(head -c 200 "$R/workload/oracle-clean-vs-chaos.json")"

        stop_gateway
        python3 "$COLLECT" "$R"; rc=$?
        log "summary: $R/summary.json (rc=$rc)"
        exit "$rc"
      }

      case "''${1:-}" in
        run)    shift; cmd_run "$@" ;;
        build)  shift; cmd_build "$@" ;;
        kill)   cmd_kill ;;
        status) cmd_status ;;
        *) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
      esac
    '';
  };
in
{
  options.hyper-modern-nixos.soakRig = {
    enable = lib.mkEnableOption "the NativeLink soak rig (rechaos gateway + chaos monkey + workload)";

    targetHost = lib.mkOption {
      type = lib.types.str;
      default = "nl-az-a.osiris-walleye.ts.net";
      description = "The site's scheduler (public REAPI port + /metrics + worker_api host), by tailnet name.";
    };

    targetPort = lib.mkOption {
      type = lib.types.port;
      default = 50051;
    };

    expectedWorkers = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Workers the site should register before a run starts (best effort).";
    };

    durationSeconds = lib.mkOption {
      type = lib.types.int;
      default = 4 * 3600;
      description = "Default campaign length for `soak run` / soak-run.service.";
    };

    seeds = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [
        20261013
        424242
      ];
    };

    killEverySeconds = lib.mkOption {
      type = lib.types.int;
      default = 900;
      description = "Mean interval between scheduler SIGKILLs during the monkey phase (0 = off).";
    };

    killJitterSeconds = lib.mkOption {
      type = lib.types.int;
      default = 300;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      soak
      rechaos
      py
    ];

    environment.etc."soak/env".text = ''
      # Defaults for soak-run.service; `soak` reads the same names from its env.
      SOAK_TARGET_HOST=${cfg.targetHost}
      SOAK_TARGET_PORT=${toString cfg.targetPort}
      SOAK_DURATION_S=${toString cfg.durationSeconds}
    '';

    # One campaign per `systemctl start --no-block soak-run`; artifacts persist
    # under /var/lib/soak/runs. The rig's root key (shipped by nixos-anywhere
    # --extra-files) lives beside them.
    systemd.services.soak-run = {
      description = "NativeLink soak campaign (rechaos) against ${cfg.targetHost}";
      after = [
        "network-online.target"
        "tailscaled.service"
      ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${soak}/bin/soak run";
        EnvironmentFile = "-/etc/soak/env";
        StateDirectory = "soak";
        WorkingDirectory = "/var/lib/soak";
        TimeoutStartSec = "infinity";
        KillMode = "control-group";
        KillSignal = "SIGINT";
      };
    };

    systemd.tmpfiles.rules = [ "d /var/lib/soak/runs 0755 root root -" ];
  };
}
