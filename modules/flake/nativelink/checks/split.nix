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
#   - the worker registers with the scheduler over the worker API
#   - the point of the split: SIGKILL the worker and the CAS and the scheduler
#     keep their PIDs while the worker comes back and registers again
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
      split.enable = true;
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

    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 4096;
  };

  testScript = ''
    start_all()

    for p in ("cas", "scheduler", "worker"):
        node.wait_for_unit(f"nativelink-{p}.service")
        exec_start = node.succeed(f"systemctl show -p ExecStart --value nativelink-{p}.service")
        assert f"-railgun-processes/{p}.json" in exec_start, f"{p} runs {exec_start!r}"

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

    registered = "journalctl -u nativelink-worker.service -o cat | grep -c 'Worker registered with scheduler'"
    node.wait_until_succeeds(f"[ $({registered}) -ge 1 ]", timeout=120)

    def main_pid(unit):
        return node.succeed(f"systemctl show -p MainPID --value {unit}").strip()

    cas_pid = main_pid("nativelink-cas.service")
    scheduler_pid = main_pid("nativelink-scheduler.service")
    node.succeed("systemctl kill -s KILL nativelink-worker.service")
    node.wait_until_succeeds(f"[ $({registered}) -ge 2 ]", timeout=120)
    assert main_pid("nativelink-cas.service") == cas_pid, "the CAS restarted with the worker"
    assert main_pid("nativelink-scheduler.service") == scheduler_pid, "the scheduler restarted with the worker"

    print("// nativelink-split // processes loaded, own their ports, survive a worker crash: OK")
  '';
}
