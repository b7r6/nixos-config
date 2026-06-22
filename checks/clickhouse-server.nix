# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                          // hyper-modern-nixos // checks // clickhouse-server
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Proves the Stage-2 SERVER-talks-to-REMOTE-KEEPER path, as a self-contained
# 4-node NixOS VM test: three Keeper-only nodes (keeper1/2/3) + one ClickHouse
# server (chserver) that is NOT a Keeper member — exactly the deliberate split
# topology (server on watchtower, ensemble elsewhere). It proves:
#
#   1. the server connects to the remote ensemble (system.zookeeper is readable);
#   2. `ON CLUSTER` distributed DDL executes (the DDL queue runs through Keeper);
#   3. a ReplicatedMergeTree table registers its replica in Keeper and accepts
#      writes/reads (the coordination round-trip that's the whole point).
#
# Local disk here (no R2 — the S3 disk is a backend swap, orthogonal to the
# coordination wiring under test). Config XML is kept in lock-step with
# modules/nixos/clickhouse.nix.
{ pkgs }:
let
  smokeTest = pkgs.callPackage ../packages/clickhouse-keeper-smoke-test { };

  keeperNames = [
    "keeper1"
    "keeper2"
    "keeper3"
  ];

  clientPort = 9181;
  raftPort = 9444;
  nativePort = 9000;
  clusterName = "fleet";

  raftServers = pkgs.lib.concatStrings (
    pkgs.lib.imap1 (id: name: ''
      <server><id>${toString id}</id><hostname>${name}</hostname><port>${toString raftPort}</port></server>
    '') keeperNames
  );

  zookeeperNodes = pkgs.lib.concatStrings (
    map (name: ''
      <node><host>${name}</host><port>${toString clientPort}</port></node>
    '') keeperNames
  );

  mkKeeperConfig =
    serverId:
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
            <force_sync>false</force_sync>
            <compress_logs>true</compress_logs>
          </coordination_settings>
          <raft_configuration>
      ${raftServers}    </raft_configuration>
        </keeper_server>
      </clickhouse>
    '';

  # Server overrides — mirrors modules/nixos/clickhouse.nix serverConfigXml, minus
  # the S3 disk (local storage in the VM). Single shard, single replica = chserver.
  serverConfig = pkgs.writeText "clickhouse-server-overrides.xml" ''
    <clickhouse>
      <listen_host>::</listen_host>
      <zookeeper>
    ${zookeeperNodes}  </zookeeper>
      <distributed_ddl><path>/clickhouse/task_queue/ddl</path></distributed_ddl>
      <remote_servers>
        <${clusterName}>
          <shard>
            <internal_replication>true</internal_replication>
            <replica><host>chserver</host><port>${toString nativePort}</port></replica>
          </shard>
        </${clusterName}>
      </remote_servers>
      <macros>
        <cluster>${clusterName}</cluster>
        <shard>01</shard>
        <replica>chserver</replica>
      </macros>
    </clickhouse>
  '';

  mkKeeperNode = serverId: { pkgs, ... }: {
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
      description = "ClickHouse Keeper";
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
    virtualisation.memorySize = 1536;
    virtualisation.diskSize = 4096;
  };
in
pkgs.testers.runNixOSTest {
  name = "clickhouse-server";

  nodes = {
    keeper1 = mkKeeperNode 1;
    keeper2 = mkKeeperNode 2;
    keeper3 = mkKeeperNode 3;

    chserver = _: {
      services.clickhouse.enable = true;
      environment.etc."clickhouse-server/config.d/hyper-modern.xml".source = serverConfig;
      networking.firewall.allowedTCPPorts = [ nativePort ];
      virtualisation.memorySize = 3072;
      virtualisation.diskSize = 6144;
    };
  };

  testScript = ''
    start_all()

    keepers = [keeper1, keeper2, keeper3]

    # ── ensemble up first ──
    for m in keepers:
        m.wait_for_unit("clickhouse-keeper.service")
        m.wait_for_open_port(${toString clientPort})

    state_cmd = "${pkgs.lib.getExe smokeTest} --host 127.0.0.1 --port ${toString clientPort} --server-state"
    for m in keepers:
        m.wait_until_succeeds(state_cmd + " | grep -E 'leader|follower'")
    keeper1.log("keeper ensemble quorum up")

    # ── server up + connected to the REMOTE ensemble ──
    chserver.wait_for_unit("clickhouse.service")
    chserver.wait_for_open_port(${toString nativePort})

    def ch(q):
        return chserver.succeed(f"clickhouse-client --query \"{q}\"")

    # 1. server sees the cluster + can read Keeper (system.zookeeper).
    chserver.wait_until_succeeds(
        "clickhouse-client --query \"SELECT count() FROM system.clusters WHERE cluster='${clusterName}'\" | grep -qv '^0$'"
    )
    chserver.wait_until_succeeds(
        "clickhouse-client --query \"SELECT name FROM system.zookeeper WHERE path='/'\""
    )
    chserver.log("server connected to remote Keeper ensemble (system.zookeeper readable)")

    # 2. ON CLUSTER distributed DDL (runs through the Keeper DDL queue).
    ch("CREATE DATABASE IF NOT EXISTS app ON CLUSTER '${clusterName}'")
    ch(
        "CREATE TABLE app.events ON CLUSTER '${clusterName}' "
        "(id UInt64, msg String) "
        "ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/app/events', '{replica}') "
        "ORDER BY id"
    )
    chserver.log("ON CLUSTER DDL + ReplicatedMergeTree created (registered in Keeper)")

    # 3. the replicated table registered its metadata in Keeper, and writes/reads work.
    ch("INSERT INTO app.events SELECT number, 'e' FROM numbers(1000)")
    out = ch("SELECT count() FROM app.events").strip()
    assert out == "1000", f"expected 1000 rows, got {out!r}"

    # the replica path exists in Keeper — the coordination round-trip we care about.
    chserver.succeed(
        "clickhouse-client --query \""
        "SELECT count() FROM system.zookeeper WHERE path='/clickhouse/tables/01/app/events/replicas'\" "
        "| grep -qv '^0$'"
    )
    chserver.log("ReplicatedMergeTree write/read OK + replica registered in Keeper — Stage 2 proven")
  '';
}
