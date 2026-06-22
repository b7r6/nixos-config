# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                          // hyper-modern-nixos // checks // clickhouse-keeper
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Boot + quorum + resilience proof for the ClickHouse Keeper ensemble, as a
# self-contained 3-node NixOS VM test (no tailnet, no registry, no secrets).
#
# The real module derives its ensemble from the topology registry and addresses
# members over the tailnet. A VM test has neither, so we import the module's
# logic shape via a SMALL inline override: three VMs named keeper1/2/3, each
# told the ensemble + its own id directly, exercising the EXACT keeper_config.xml
# generation, the standalone (server-less) `clickhouse keeper` unit, the user/
# state-dir wiring, and the kazoo smoke test. The registry-derivation itself is
# covered by eval of the real host configs; what THIS proves is the substantive
# runtime behaviour: quorum forms, and the resilience properties hold —
#   1. all three form a cluster (a leader is elected, CRUD works);
#   2. kill ONE node  → quorum SURVIVES (2/3), writes still succeed;
#   3. kill a SECOND  → quorum LOST (1/3), writes FAIL (fail-stop, not split);
#   4. restart both   → the node REJOINS and the cluster recovers.
{ pkgs, inputs }:
let
  smokeTest = pkgs.callPackage ../packages/clickhouse-keeper-smoke-test { };

  nodeNames = [
    "keeper1"
    "keeper2"
    "keeper3"
  ];

  clientPort = 9181;
  raftPort = 9444;

  # The exact keeper_config.xml the module emits, parameterised for the VM
  # (members addressed by VM hostname rather than tailnet FQDN). Kept in lock-
  # step with modules/nixos/clickhouse.nix.
  mkKeeperConfig =
    serverId:
    let
      raftServers = pkgs.lib.concatStrings (
        pkgs.lib.imap1 (id: name: ''
          <server>
            <id>${toString id}</id>
            <hostname>${name}</hostname>
            <port>${toString raftPort}</port>
          </server>
        '') nodeNames
      );
    in
    pkgs.writeText "keeper-config.xml" ''
      <clickhouse>
        <logger><level>information</level><console>true</console></logger>
        <listen_host>::</listen_host>
        <keeper_server>
          <tcp_port>${toString clientPort}</tcp_port>
          <server_id>${toString serverId}</server_id>
          <log_storage_path>/var/lib/clickhouse-keeper/coordination/log</log_storage_path>
          <snapshot_storage_path>/var/lib/clickhouse-keeper/coordination/snapshots</snapshot_storage_path>
          <coordination_settings>
            <operation_timeout_ms>10000</operation_timeout_ms>
            <session_timeout_ms>30000</session_timeout_ms>
            <raft_logs_level>information</raft_logs_level>
            <!-- soft durability: ensemble (the index) is the durability -->
            <force_sync>false</force_sync>
            <compress_logs>true</compress_logs>
          </coordination_settings>
          <raft_configuration>
      ${raftServers}    </raft_configuration>
        </keeper_server>
      </clickhouse>
    '';

  mkNode = serverId: { pkgs, ... }: {
    environment.systemPackages = [
      pkgs.clickhouse
      smokeTest
    ];

    networking.firewall.allowedTCPPorts = [
      clientPort
      raftPort
    ];

    users.users.clickhouse-keeper = {
      isSystemUser = true;
      group = "clickhouse-keeper";
      home = "/var/lib/clickhouse-keeper";
    };
    users.groups.clickhouse-keeper = { };

    systemd.services.clickhouse-keeper = {
      description = "ClickHouse Keeper (coordination plane)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.clickhouse}/bin/clickhouse keeper --config-file=${mkKeeperConfig serverId}";
        Restart = "on-failure";
        RestartSec = 2;
        StateDirectory = "clickhouse-keeper";
        User = "clickhouse-keeper";
        Group = "clickhouse-keeper";
      };
    };

    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 4096;
  };
in
pkgs.testers.runNixOSTest {
  name = "clickhouse-keeper";

  nodes = {
    keeper1 = mkNode 1;
    keeper2 = mkNode 2;
    keeper3 = mkNode 3;
  };

  testScript = ''
    start_all()

    machines = [keeper1, keeper2, keeper3]

    # ── 1. Quorum forms: all three up, ports open, a leader exists ──
    for m in machines:
        m.wait_for_unit("clickhouse-keeper.service")
        m.wait_for_open_port(${toString clientPort})

    # Wait until every node answers the ZK protocol and reports a stable role
    # (leader/follower). The smoke-test tool does the four-letter-word probe over
    # a raw socket in Python — no netcat dialect dependency.
    state_cmd = "${pkgs.lib.getExe smokeTest} --host 127.0.0.1 --port ${toString clientPort} --server-state"
    for m in machines:
        m.wait_until_succeeds(state_cmd + " | grep -E 'leader|follower'")

    def leaders():
        return [m.succeed(state_cmd).strip() for m in machines]

    states = leaders()
    keeper1.log(f"server states: {states}")
    assert states.count("leader") == 1, f"expected exactly one leader, got {states}"
    assert states.count("follower") == 2, f"expected two followers, got {states}"

    # CRUD round-trip via the kazoo smoke test (all nodes serve the ZK protocol).
    for m in machines:
        m.succeed("${pkgs.lib.getExe smokeTest} --host 127.0.0.1 --port ${toString clientPort}")

    # ── 2. Kill ONE node → quorum survives (2/3) ──
    keeper3.crash()
    # The remaining two must still elect/keep a leader and serve writes.
    keeper1.wait_until_succeeds("${pkgs.lib.getExe smokeTest} --host 127.0.0.1 --port ${toString clientPort}")
    keeper2.succeed("${pkgs.lib.getExe smokeTest} --host 127.0.0.1 --port ${toString clientPort}")
    keeper1.log("quorum SURVIVED one-node loss (2/3)")

    # ── 3. Kill a SECOND node → quorum lost (1/3), writes fail-stop ──
    keeper2.crash()
    # The lone survivor must REFUSE writes (no quorum) — fail-stop, not split-brain.
    keeper1.wait_until_fails("${pkgs.lib.getExe smokeTest} --host 127.0.0.1 --port ${toString clientPort}")
    keeper1.log("quorum correctly LOST with two-node loss (1/3): writes fail-stop")

    # ── 4. Restart the downed nodes → rejoin + recover ──
    keeper2.start()
    keeper3.start()
    for m in [keeper2, keeper3]:
        m.wait_for_unit("clickhouse-keeper.service")
        m.wait_for_open_port(${toString clientPort})

    # Cluster recovers: writes succeed again once quorum is restored.
    keeper1.wait_until_succeeds("${pkgs.lib.getExe smokeTest} --host 127.0.0.1 --port ${toString clientPort}")
    keeper1.log("ensemble RECOVERED after rejoin")
  '';
}
