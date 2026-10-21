# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                             // hyper-modern-nixos // checks // nativelink-split
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# SERVE-correctness proof for a `split` host (fleet.dhall layout, ../split.nix):
# railgun's own rendered processes, booted as their own units in a VM.
#
#   - each process config loads: nativelink validates its whole config at
#     startup and exits on anything malformed, so a live unit is the proof
#   - each port is held by the process that owns it (cas :50052, scheduler
#     :50051 + :50061), and the fork's monolithic unit is masked
#   - every worker registers with the scheduler over the worker API, each from
#     its own work directory, and the scheduler gauges all three
#   - the point of the split: SIGKILL one worker and the CAS, the scheduler and
#     the other workers keep their PIDs while it comes back and registers again
#
# Fake R2 creds (test secret in the store on purpose) so the cas process's
# ${R2_*} refs expand; the slow tier is never reached.
{ pkgs, inputs }:
let
  inherit (inputs) self;

  testR2Env = pkgs.writeText "nativelink-test-r2-env" ''
    R2_ACCESS_KEY_ID=test-access-key
    R2_SECRET_ACCESS_KEY=test-secret-key
  '';
in
pkgs.testers.runNixOSTest {
  name = "nativelink-split";

  nodes.node = { ... }: {
    imports = [
      ../../../nixos/state.nix
      ../../../nixos/otel.nix
      ../../registry/nixos.nix
      inputs.nativelink-nix.nixosModules.nativelink
      ../shim.nix
      ../split.nix
    ];

    _module.args.flake = {
      inherit self inputs;
      config = { };
    };

    hyper-modern-nixos.nativelink = {
      enable = true;
      dhallHost = "railgun";
      split = {
        enable = true;
        workers = 3;
      };
      openFirewall = false;
      r2 = {
        enable = true;
        accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
        bucket = "straylight-nativelink-cas";
        environmentFile = "${testR2Env}";
      };
    };

    # railgun dials itself by its fleet fqdn (configurations/nixos/railgun).
    networking.hosts."127.0.0.1" = [ "railgun.sk1.s4.gl" ];

    environment.systemPackages = [ pkgs.curl ];

    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 4096;
  };

  testScript = ''
    start_all()

    workers = [f"worker-{n}" for n in (1, 2, 3)]

    def exec_start(p):
        return node.succeed(f"systemctl show -p ExecStart --value nativelink-{p}.service")

    for p in ["cas", "scheduler"] + workers:
        node.wait_for_unit(f"nativelink-{p}.service")
        assert f"-nativelink-railgun-{p}.json" in exec_start(p), f"{p} runs {exec_start(p)!r}"

    node.wait_for_open_port(50052)  # cas
    node.wait_for_open_port(50051)  # scheduler: public
    node.wait_for_open_port(50061)  # scheduler: worker_api

    def owner(port):
        pid = node.succeed(
            f"ss -ltnpH 'sport = :{port}' | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2"
        ).strip()
        return node.succeed(f"cat /proc/{pid}/cgroup")

    for port, unit in ((50052, "nativelink-cas.service"),
                       (50051, "nativelink-scheduler.service"),
                       (50061, "nativelink-scheduler.service")):
        cgroup = owner(port)
        assert unit in cgroup, f":{port} is served from {cgroup!r}, expected {unit}"

    assert node.succeed("systemctl is-enabled nativelink.service || true").strip() == "masked"

    # The work directory is wiped at startup, so no two workers may share one.
    work_dirs = {
        w: node.succeed(
            "grep -oE '\"work_directory\": *\"[^\"]+\"' "
            + exec_start(w).split("argv[]=")[-1].split()[1]
        ).strip()
        for w in workers
    }
    assert len(set(work_dirs.values())) == len(workers), f"shared work directories: {work_dirs}"

    def registered(w):
        return f"journalctl -u nativelink-{w}.service -o cat | grep -c 'Worker registered with scheduler'"

    for w in workers:
        node.wait_until_succeeds(f"[ $({registered(w)}) -ge 1 ]", timeout=120)

    gauged = "curl -s localhost:50051/metrics | grep -oE 'workers_workers_[0-9a-f_]+_connected_timestamp' | sort -u | wc -l"
    node.wait_until_succeeds(f"[ $({gauged}) -eq {len(workers)} ]", timeout=120)

    def main_pid(unit):
        return node.succeed(f"systemctl show -p MainPID --value {unit}").strip()

    others = [f"nativelink-{p}.service" for p in ("cas", "scheduler", "worker-1", "worker-3")]
    before = {u: main_pid(u) for u in others}
    node.succeed("systemctl kill -s KILL nativelink-worker-2.service")
    node.wait_until_succeeds(f"[ $({registered('worker-2')}) -ge 2 ]", timeout=120)
    for u in others:
        assert main_pid(u) == before[u], f"{u} restarted when worker-2 was killed"

    print("// nativelink-split // scheduler, cas and three workers loaded, own their ports and paths, survive a worker crash: OK")
  '';
}
