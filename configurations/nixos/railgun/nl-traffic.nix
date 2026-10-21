# railgun — nl-traffic: continuous Bazel traffic against the local scheduler so
# the console's build view always has recent invocations: the synthetic
# workspace (orbital-nativelink/traffic/rbe-smoke, docs/TRAFFIC.md) and real
# code (bazelbuild/buildtools, traffic/real/buildtools/README.md). Every run
# publishes to the BES when nl-bes answers, with a known invocation id, and
# posts the compact execution log afterwards so nl-bes can enrich actions with
# timings and workers. One run at a time, nice 10, every 5 minutes.
{ pkgs, lib, ... }:
let
  srcDir = "/home/b7r6/src/hypermodern/orbital-nativelink/traffic/rbe-smoke";
  goTests = "/home/b7r6/src/hypermodern/orbital-nativelink/traffic/real/buildtools/go_tests.txt";
  realDir = "/home/b7r6/real/buildtools"; # cloned once, see the README
  stateDir = "/var/lib/nl-traffic";
  run = pkgs.writeShellApplication {
    name = "nl-traffic-run";
    # gcc/binutils: Bazel's local_config_cc must find a compiler or sh_test
    # analysis aborts on the launcher target; actions still run remotely.
    runtimeInputs = with pkgs; [ bazel_7 gcc binutils nix curl coreutils rsync gnugrep util-linux git ];
    text = ''
      set -euo pipefail
      export HOME=${stateDir}/home; mkdir -p "$HOME" ${stateDir}/ws ${stateDir}/logs
      # Bazel 9 for the real project (its .bazelversion): the pinned nixpkgs'
      # bazel_9 is a placeholder derivation, so it comes from the flake registry
      # like the interactive runs.
      b9() { nix shell nixpkgs#bazel_9 -c bazel "$@"; }

      # Deterministic C++ toolchain configuration for every invocation: pin the
      # compiler local_config_cc resolves, instead of letting it probe PATH.
      cc_flags=(--repo_env=CC=${pkgs.gcc}/bin/gcc --repo_env=BAZEL_USE_CPP_ONLY_TOOLCHAIN=1)

      bes=()
      if curl -sf --max-time 3 http://127.0.0.1:3311/api/bes/healthz >/dev/null; then bes=(--config=bes); fi

      # run_bazel <bazel|b9> <command> [args…]: known invocation id, compact exec
      # log, and the post of that log to nl-bes once the build is over.
      run_bazel() {
        local tool="$1" cmd="$2"; shift 2
        local id; id=$(uuidgen)
        local log=${stateDir}/logs/execlog-$id.zst
        set +e
        "$tool" "$cmd" "$@" "''${cc_flags[@]}" "''${bes[@]}" \
          --invocation_id="$id" --execution_log_compact_file="$log"
        local rc=$?
        set -e
        if [ ''${#bes[@]} -gt 0 ] && [ -s "$log" ]; then
          if curl -sf -X POST --data-binary @"$log" "http://127.0.0.1:3311/api/bes/invocations/$id/execlog" >/dev/null; then
            echo "execlog posted for $id ($(stat -c %s "$log") bytes)"
          else
            echo "execlog POST failed for $id"
          fi
        fi
        rm -f "$log"
        echo "invocation $id exit $rc (bes: ''${#bes[@]})"
        return 0
      }

      shape=''${NL_SHAPE:-$(( ($(date +%s) / 300) % 7 ))}
      export SALT=$RANDOM
      case $shape in
        0|1|2|3|4)
          rsync -a --delete --exclude 'bazel-*' ${srcDir}/ ${stateDir}/ws/
          cd ${stateDir}/ws
          case $shape in
            0) echo "shape 0: build //:all (cached)";                 run_bazel bazel build //:all ;;
            1) echo "shape 1: build //:all --config=rebuild SALT=$SALT"; run_bazel bazel build //:all --config=rebuild ;;
            2) echo "shape 2: test //:tests";                          run_bazel bazel test //:tests ;;
            3) echo "shape 3: test //:tests --config=failing";         run_bazel bazel test //:tests --config=failing ;;
            4) echo "shape 4: build //:fail_all --config=rebuild --config=failing"; run_bazel bazel build //:fail_all --config=rebuild --config=failing ;;
          esac
          bazel shutdown || true ;;
        5|6)
          if [ ! -d ${realDir} ]; then echo "no ${realDir}; skipping real shape"; exit 0; fi
          mkdir -p ${stateDir}/buildtools
          rsync -a --delete --exclude 'bazel-*' ${realDir}/ ${stateDir}/buildtools/
          cd ${stateDir}/buildtools
          if [ "$shape" = 5 ]; then
            echo "shape 5: buildtools build //buildifier //buildozer //unused_deps"
            run_bazel b9 build //buildifier //buildozer //unused_deps
          else
            echo "shape 6: buildtools test (14 go_test, --nocache_test_results)"
            mapfile -t gotests < ${goTests}
            run_bazel b9 test "''${gotests[@]}" --nocache_test_results
          fi
          b9 shutdown || true ;;
      esac
    '';
  };
in
{
  systemd.tmpfiles.rules = [ "d ${stateDir} 0755 b7r6 users -" ];

  systemd.services.nl-traffic = {
    description = "Bazel traffic against the local NativeLink (console build view)";
    after = [ "nativelink-scheduler.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "b7r6";
      Group = "users";
      Nice = 10;
      WorkingDirectory = stateDir;
      ExecStart = "${run}/bin/nl-traffic-run";
      TimeoutStartSec = "20min";
    };
  };

  systemd.timers.nl-traffic = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitInactiveSec = "5min";
      RandomizedDelaySec = "30s";
      Unit = "nl-traffic.service";
    };
  };
}
