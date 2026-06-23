# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                   // hyper-modern-nixos // checks // nativelink
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# SERVE-correctness proof for the NativeLink remote-execution config, as a
# self-contained NixOS VM test. The config is now rendered at eval time via IFD
# from the typed Dhall fleet (nativelink/fleet.dhall → render-all.dhall), NOT a
# committed out/<host>.json. A silently-wrong RE config quietly corrupts the
# fleet's content-addressed build store (wrong shard weights, a worker dialing
# the wrong scheduler) — so this boots a real nativelink node on the IFD-rendered
# config and proves the daemon actually loads it and serves:
#
#   - the scheduler `public` endpoint binds :50051
#   - the CAS server binds :50052
#   - the worker_api binds :50061
#   - the rendered config is the Dhall fleet's (sharded CAS, MAIN_SCHEDULER), NOT
#     a leaked/empty config — a malformed config makes nativelink exit at startup,
#     so a live, port-bound daemon IS the proof the IFD render is well-formed.
#
# We use dhallHost = "watchtower" (the scheduler role: CAS + scheduler + worker —
# the richest config, exercising the shard ring, scheduler props, and worker). R2
# is the slow tier; we give it FAKE creds (test secret in the store on purpose)
# so the ${R2_*} env refs resolve and the daemon starts.
{ pkgs, inputs }:
let
  inherit (inputs) self;

  # Fake R2 creds so the rendered config's ${R2_ACCESS_KEY_ID}/${...SECRET} expand
  # and nativelink starts. Test-only, in the store on purpose (no agenix).
  testR2Env = pkgs.writeText "nativelink-test-r2-env" ''
    R2_ACCESS_KEY_ID=test-access-key
    R2_SECRET_ACCESS_KEY=test-secret-key
  '';
in
pkgs.testers.runNixOSTest {
  name = "nativelink";

  nodes.node = { ... }: {
    imports = [
      ../../../nixos/state.nix
      ../../registry/nixos.nix
      ../nixos.nix
    ];

    # nativelink.nix reads flake.self (to locate nativelink/) + flake.inputs
    # (the nativelink package). Provide the same specialArg the fleet passes.
    _module.args.flake = {
      inherit self inputs;
      config = { };
    };

    hyper-modern-nixos.nativelink = {
      enable = true;
      dhallHost = "watchtower"; # scheduler role: CAS + scheduler + worker
      openFirewall = false; # tailnet-only in prod; irrelevant in the VM
      r2 = {
        enable = true;
        accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
        bucket = "straylight-nativelink-cas";
        environmentFile = "${testR2Env}";
      };
    };

    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 4096;
  };

  testScript = ''
    start_all()

    # The daemon comes up ONLY if the IFD-rendered config parses and is valid —
    # nativelink validates its whole config at startup and exits non-zero on any
    # malformed store/scheduler/server. A live unit is the serve-correctness proof.
    node.wait_for_unit("nativelink.service")

    # The scheduler + CAS + worker_api endpoints from the Dhall fleet bind.
    node.wait_for_open_port(50051)  # public (scheduler/CAS/execution/capabilities)
    node.wait_for_open_port(50052)  # cas server
    node.wait_for_open_port(50061)  # worker_api

    # The rendered config is the typed-Dhall fleet's, not a leak/placeholder:
    # confirm the sharded CAS + named scheduler made it into the file the unit runs.
    cfg_path = node.succeed(
        "systemctl show -p ExecStart nativelink.service "
        "| grep -oE '/nix/store/[^ ]+\\.json' | head -1"
    ).strip()
    cfg = node.succeed(f"cat {cfg_path}")
    assert "MAIN_SCHEDULER" in cfg, "scheduler missing from rendered config"
    assert "CAS_MAIN_STORE" in cfg, "sharded CAS store missing from rendered config"
    assert "grpc://guccimane.sju1.s4.gl:50052" in cfg, \
        "CAS shard ring missing a peer (fleet topology not rendered)"
    # the R2 slow tier env-refs survived rendering (creds come from EnvironmentFile)
    assert "straylight-nativelink-cas" in cfg, "R2 slow tier missing from config"

    print("// nativelink // IFD-rendered typed-Dhall config loaded + served: OK")
  '';
}
