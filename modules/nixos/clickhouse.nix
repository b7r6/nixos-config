# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                           // hyper-modern-nixos // clickhouse
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# ClickHouse, OFF BY DEFAULT, under hyper-modern-nixos.databases.clickhouse —
# alongside databases.postgres / databases.redis.
#
# Stage 1 (THIS FILE for now): the KEEPER role only — the coordination plane.
# nixpkgs ships services.clickhouse (the server) but NO Keeper module, so Keeper
# is a hand-rolled systemd service around `clickhouse keeper -C <config>` (same
# "no upstream module, wrap the binary" shape as nativelink). The SERVER role
# (databases.clickhouse.server.*) lands in Stage 2.
#
# Deliberate topology (see docs/infrastructure/clickhouse.md): the Keeper
# ensemble is NOT co-located with the ClickHouse server. The three ensemble
# members (ultraviolence/guccimane/shimmer) run Keeper ONLY — no co-located
# `services.clickhouse` — and the server (watchtower) dials them over the
# tailnet. This exercises coordination-plane latency/partition for real, and the
# ensemble is multi-arch (shimmer is aarch64).
#
# The ensemble is DERIVED FROM THE TOPOLOGY REGISTRY: every host tagged with the
# `clickhouse-keeper` service is a member, sorted by physical name for a stable
# Raft server_id assignment. Adding/moving a node is a registry edit + re-render,
# exactly like CoreDNS service records — never a hand-maintained node list.
#
# State: Keeper's coordination log + snapshots are small and rebuildable from
# quorum, so /var/lib/clickhouse-keeper is `reconstructible` (persisted across an
# impermanence reboot, never restic'd). Exposure: tailnet-only — the client
# (:9181, ZooKeeper protocol) and raft (:9444) ports are opened on tailscale0
# only (the firewall is on fleet-wide).
{
  config,
  lib,
  pkgs,
  flake ? null,
  ...
}:
let
  cfg = config.hyper-modern-nixos.databases.clickhouse;
  inherit (cfg) keeper;
  machineSecrets = flake.self + "/secrets/agenix/machines";

  topo = config.hyper-modern-nixos.topology;

  # ── Ensemble, derived from the topology registry ────────────────────────────
  # Every host tagged `clickhouse-keeper`, sorted by physical name so the Raft
  # server_id assignment (index + 1) is stable and deployment-order-independent.
  ensembleHosts = lib.sort (a: b: a.physical < b.physical) (
    lib.attrValues (topo.helpers.hostsWithService "clickhouse-keeper")
  );

  # How a member is addressed in the raft_configuration / zookeeper blocks.
  #   "tailnet-fqdn" → <tailnet>.<tailnetSuffix> (MagicDNS; resolves fleet-wide)
  #   "tailnet-ip"   → tailnet_ipv4 (pin past DNS, e.g. for early-boot races)
  addrOf =
    h:
    if keeper.nodeAddressMode == "tailnet-ip" then
      h.tailnet_ipv4
    else
      "${h.tailnet}.${topo.registry.tailnetSuffix}";

  # This host's 1-based index in the ensemble = its Raft server_id.
  selfIndex = lib.lists.findFirstIndex (
    h: h.physical == config.networking.hostName
  ) null ensembleHosts;
  serverId = if selfIndex == null then null else selfIndex + 1;

  # ── keeper_config.xml ───────────────────────────────────────────────────────
  raftServers = lib.concatStrings (
    lib.imap1 (id: h: ''
      <server>
        <id>${toString id}</id>
        <hostname>${addrOf h}</hostname>
        <port>${toString keeper.ports.raft}</port>
      </server>
    '') ensembleHosts
  );

  keeperConfig = ''
    <clickhouse>
      <logger>
        <level>${keeper.logLevel}</level>
        <console>true</console>
      </logger>

      <listen_host>::</listen_host>
      <max_connections>4096</max_connections>

      <prometheus>
        <endpoint>/metrics</endpoint>
        <port>${toString keeper.ports.prometheus}</port>
        <metrics>true</metrics>
        <events>true</events>
        <asynchronous_metrics>true</asynchronous_metrics>
      </prometheus>

      <keeper_server>
        <tcp_port>${toString keeper.ports.client}</tcp_port>
        <server_id>${toString serverId}</server_id>

        <log_storage_path>${keeper.dataDir}/coordination/log</log_storage_path>
        <snapshot_storage_path>${keeper.dataDir}/coordination/snapshots</snapshot_storage_path>

        <coordination_settings>
          <!-- Bumped from co-located defaults: Raft crosses the tailnet here,
               not loopback. Tuning these IS part of the resilience rehearsal. -->
          <operation_timeout_ms>${toString keeper.operationTimeoutMs}</operation_timeout_ms>
          <session_timeout_ms>${toString keeper.sessionTimeoutMs}</session_timeout_ms>
          <raft_logs_level>${keeper.raftLogsLevel}</raft_logs_level>
          <!-- Soft durability: don't fsync each Raft log append. A write is
               durable once committed to the quorum-majority's REPLICATED LOG
               (the index) — the ensemble IS the durability, not the disk. Trades
               single-node fsync-crash-safety for throughput; the right call for
               a 3-node ensemble and the docs' own tuning recommendation. With
               force_sync off, any disk type (incl. S3-tiered) is usable for log
               storage. compress_logs pairs naturally (less Raft-log disk I/O). -->
          <force_sync>${if keeper.forceSync then "true" else "false"}</force_sync>
          <compress_logs>${if keeper.compressLogs then "true" else "false"}</compress_logs>
        </coordination_settings>

        <raft_configuration>
    ${raftServers}    </raft_configuration>
      </keeper_server>
    </clickhouse>
  '';

  keeperConfigFile = pkgs.writeText "keeper-config.xml" keeperConfig;

  smokeTest = pkgs.callPackage ../../packages/clickhouse-keeper-smoke-test { };

  # ── Server role ─────────────────────────────────────────────────────────────
  inherit (cfg) server;

  # The server points <zookeeper> at the REMOTE Keeper ensemble (the three
  # registry-tagged nodes), addressed exactly like the raft config above.
  zookeeperNodes = lib.concatStrings (
    map (h: ''
      <node>
        <host>${addrOf h}</host>
        <port>${toString keeper.ports.client}</port>
      </node>
    '') ensembleHosts
  );

  # A single-shard/single-replica cluster defined NOW so all DDL is `ON CLUSTER`
  # and every table is ReplicatedMergeTree from day one. Growing the fleet later
  # = adding <replica>/<shard> entries (+ a registry tag), not a schema rewrite.
  remoteServers = ''
    <${server.clusterName}>
      <shard>
        <internal_replication>true</internal_replication>
        <replica>
          <host>${config.networking.hostName}.${topo.registry.tailnetSuffix}</host>
          <port>${toString server.ports.native}</port>
        </replica>
      </shard>
    </${server.clusterName}>
  '';

  # S3-disk storage policy: the R2 bucket is the durable tier, fronted by a local
  # filesystem cache. Creds arrive as AWS_* env from the agenix file (never the
  # store) via `use_environment_credentials`.
  s3StorageXml = lib.optionalString server.s3.enable ''
    <storage_configuration>
      <disks>
        <s3_r2>
          <type>s3</type>
          <endpoint>${server.s3.endpoint}/${server.s3.bucket}/${config.networking.hostName}/</endpoint>
          <use_environment_credentials>true</use_environment_credentials>
          <region>${server.s3.region}</region>
        </s3_r2>
        <s3_r2_cache>
          <type>cache</type>
          <disk>s3_r2</disk>
          <path>${server.dataDir}/s3_cache/</path>
          <max_size>${toString server.s3.cacheMaxBytes}</max_size>
        </s3_r2_cache>
      </disks>
      <policies>
        <s3_main>
          <volumes>
            <main>
              <disk>s3_r2_cache</disk>
            </main>
          </volumes>
        </s3_main>
      </policies>
    </storage_configuration>
  '';

  serverConfigXml = ''
    <clickhouse>
      <listen_host>${server.listenHost}</listen_host>

      <zookeeper>
    ${zookeeperNodes}  </zookeeper>

      <distributed_ddl>
        <path>/clickhouse/task_queue/ddl</path>
      </distributed_ddl>

      <remote_servers>
    ${remoteServers}  </remote_servers>

      <macros>
        <cluster>${server.clusterName}</cluster>
        <shard>01</shard>
        <replica>${config.networking.hostName}</replica>
      </macros>

      ${s3StorageXml}

      <prometheus>
        <endpoint>/metrics</endpoint>
        <port>9363</port>
        <metrics>true</metrics>
        <events>true</events>
        <asynchronous_metrics>true</asynchronous_metrics>
      </prometheus>

    </clickhouse>
  '';

  serverConfigFile = pkgs.writeText "clickhouse-server-overrides.xml" serverConfigXml;
in
{
  options.hyper-modern-nixos.databases.clickhouse = {
    package = lib.mkPackageOption pkgs "clickhouse" { };

    keeper = {
      enable = lib.mkEnableOption "ClickHouse Keeper (coordination plane, registry-derived ensemble)";

      nodeAddressMode = lib.mkOption {
        type = lib.types.enum [
          "tailnet-fqdn"
          "tailnet-ip"
        ];
        default = "tailnet-fqdn";
        description = ''
          How ensemble members address each other in the Raft config.
          tailnet-fqdn = MagicDNS names (default; resolves fleet-wide via CoreDNS).
          tailnet-ip   = pinned tailnet_ipv4 (use if early-boot DNS races Raft).
        '';
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/clickhouse-keeper";
        description = ''
          Keeper coordination dir (log + snapshots). Classified `reconstructible`
          state — it rebuilds from quorum — so it's persisted across an
          impermanence reboot but never restic'd.
        '';
      };

      logLevel = lib.mkOption {
        type = lib.types.enum [
          "trace"
          "debug"
          "information"
          "warning"
          "error"
        ];
        default = "information";
        description = "Keeper server log level.";
      };

      raftLogsLevel = lib.mkOption {
        type = lib.types.enum [
          "trace"
          "debug"
          "information"
          "warning"
          "error"
        ];
        default = "information";
        description = "NuRaft log verbosity (separate from the server logger).";
      };

      operationTimeoutMs = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10000;
        description = "Keeper operation timeout (ms). Bumped for tailnet RTT.";
      };

      sessionTimeoutMs = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30000;
        description = "Keeper session timeout (ms). Bumped for tailnet RTT.";
      };

      forceSync = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          fsync the Raft coordination log on EVERY write (hard durability).
          Default false = SOFT durability: a write is durable once replicated to
          a quorum majority's log (the index), not once fsync'd to local disk —
          the ensemble is the durability. Trades single-node fsync-crash-safety
          for throughput (the upstream tuning recommendation for a healthy
          multi-node ensemble), and lifts the local-disk-only restriction on log
          storage. Set true only for a single-node/at-risk-of-total-power-loss
          deployment.
        '';
      };

      compressLogs = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "zstd-compress the Raft log files (less disk I/O). Pairs with soft durability.";
      };

      openTailnet = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open the Keeper client + raft ports on tailscale0 only.";
      };

      smokeTest = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the post-start kazoo CRUD/ruok smoke test as a oneshot health gate.";
      };

      ports = {
        client = lib.mkOption {
          type = lib.types.port;
          default = 9181;
          description = "Keeper client port (ZooKeeper protocol).";
        };
        raft = lib.mkOption {
          type = lib.types.port;
          default = 9444;
          description = "Keeper inter-node Raft port.";
        };
        prometheus = lib.mkOption {
          type = lib.types.port;
          default = 9364;
          description = "Keeper prometheus metrics port (scraped by local OTel agent).";
        };
      };
    };

    server = {
      enable = lib.mkEnableOption "ClickHouse server (data plane; dials the remote Keeper ensemble)";

      clusterName = lib.mkOption {
        type = lib.types.str;
        default = "fleet";
        description = ''
          remote_servers cluster name. All DDL is `ON CLUSTER <clusterName>` and
          tables are ReplicatedMergeTree from day one, so scale-out is a registry
          edit, not a schema rewrite.
        '';
      };

      listenHost = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Server bind address. Default loopback: the HTTP interface (8123) is
          fronted by nginx at clickhouse.sju1.s4.gl; the native protocol (9000)
          is opened on tailscale0 only. Set "::" to bind all interfaces.
        '';
      };

      openTailnet = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open the native protocol port (9000) on tailscale0 only.";
      };

      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/clickhouse";
        description = ''
          Local working dir. With the S3 disk on, the durable truth is in R2 and
          this is the local cache → classified `reconstructible` (persisted across
          an impermanence reboot, never restic'd).
        '';
      };

      secret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "clickhouse-r2-env";
        description = ''
          agenix machine-secret NAME (decrypts to /run/agenix/<name>) providing the
          R2 creds as AWS SDK env vars (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
          for the S3 disk. Self-wired; null = wire the EnvironmentFile yourself.
          Required when s3.enable.
        '';
      };

      ports = {
        http = lib.mkOption {
          type = lib.types.port;
          default = 8123;
          description = "HTTP interface port (fronted by nginx).";
        };
        native = lib.mkOption {
          type = lib.types.port;
          default = 9000;
          description = "Native protocol port (tailscale0 only).";
        };
      };

      s3 = {
        enable = lib.mkEnableOption "S3-backed data disk to R2 (durable tier; local dir is cache)";

        bucket = lib.mkOption {
          type = lib.types.str;
          default = "straylight-clickhouse";
          description = "R2 bucket for the S3 data disk.";
        };
        endpoint = lib.mkOption {
          type = lib.types.str;
          default = "https://6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com";
          description = "R2 S3 endpoint (account-scoped). Non-secret.";
        };
        region = lib.mkOption {
          type = lib.types.str;
          default = "auto";
          description = "S3 region (R2 = auto).";
        };
        cacheMaxBytes = lib.mkOption {
          type = lib.types.ints.positive;
          default = 107374182400; # 100 GiB
          description = "Max size of the local S3 cache disk (bytes).";
        };
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf keeper.enable {
      assertions = [
        {
          assertion = serverId != null;
          message = ''
            hyper-modern-nixos.databases.clickhouse.keeper is enabled on
            ${config.networking.hostName}, but this host is not tagged
            `clickhouse-keeper` in the topology registry (registry/hosts.dhall).
            The ensemble is registry-derived; add the tag + re-render
            (nix run .#topology-render).
          '';
        }
        {
          assertion = lib.allUnique (map (h: h.physical) ensembleHosts);
          message = "clickhouse-keeper: ensemble members must be unique.";
        }
        {
          assertion = (lib.length ensembleHosts) >= 3;
          message = ''
            clickhouse-keeper: the ensemble must have at least 3 members for fault
            tolerance (found ${toString (lib.length ensembleHosts)}). A 1-node
            "ensemble" is a toy; a 2-node one is worse than 1 (any loss breaks
            quorum). Tag at least 3 hosts `clickhouse-keeper`.
          '';
        }
        {
          assertion = (lib.mod (lib.length ensembleHosts) 2) == 1;
          message = ''
            clickhouse-keeper: the ensemble size should be ODD (found
            ${toString (lib.length ensembleHosts)}). Even sizes gain no extra
            fault tolerance and risk split votes.
          '';
        }
      ];

      # Coordination dir = reconstructible (persist on impermanence, never restic'd
      # — quorum is the source of truth).
      hyper-modern-nixos.state.dirs.clickhouse-keeper = {
        path = keeper.dataDir;
        class = "reconstructible";
      };

      environment.systemPackages = [
        cfg.package # clickhouse-keeper-client for ops (mntr/ruok/etc.)
        smokeTest
      ];

      systemd.services.clickhouse-keeper = {
        description = "ClickHouse Keeper (coordination plane)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        restartTriggers = [ keeperConfigFile ];

        serviceConfig = {
          ExecStart = "${cfg.package}/bin/clickhouse keeper --config-file=${keeperConfigFile}";
          Restart = "on-failure";
          RestartSec = 5;
          # Keeper manages its own coordination dir; systemd creates + owns it.
          StateDirectory = "clickhouse-keeper";
          User = "clickhouse-keeper";
          Group = "clickhouse-keeper";
          # Hardening — Keeper is a network-facing coordination service.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          ReadWritePaths = [ keeper.dataDir ];
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
        };
      };

      users.users.clickhouse-keeper = {
        isSystemUser = true;
        group = "clickhouse-keeper";
        home = keeper.dataDir;
      };
      users.groups.clickhouse-keeper = { };

      # Post-start health gate: prove this node answers the ZK protocol + CRUDs.
      systemd.services.clickhouse-keeper-smoke-test = lib.mkIf keeper.smokeTest {
        description = "ClickHouse Keeper smoke test (kazoo CRUD + ruok)";
        after = [ "clickhouse-keeper.service" ];
        requires = [ "clickhouse-keeper.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # --wait: Keeper's unit reports started before the client port
          # listens, so the boot-time gate needs a grace window (seen on
          # ultraviolence: connection refused at t+0, imok moments later).
          ExecStart = "${lib.getExe smokeTest} --host 127.0.0.1 --port ${toString keeper.ports.client} --wait 60";
        };
      };

      # Tailnet-only exposure (enforced — firewall is on fleet-wide).
      networking.firewall.interfaces = lib.mkIf keeper.openTailnet {
        tailscale0.allowedTCPPorts = [
          keeper.ports.client
          keeper.ports.raft
        ];
      };
    })

    # ── Server role ───────────────────────────────────────────────────────────
    (lib.mkIf server.enable {
      assertions = [
        {
          assertion = (lib.length ensembleHosts) >= 1;
          message = ''
            hyper-modern-nixos.databases.clickhouse.server is enabled but no host
            is tagged `clickhouse-keeper` in the topology registry — the server
            needs a Keeper ensemble to dial. Tag the ensemble nodes + re-render.
          '';
        }
        {
          assertion = !server.s3.enable || server.secret != null;
          message = ''
            clickhouse server s3.enable is true but .secret is null. The S3 disk
            needs the R2 creds (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY) from an
            agenix env file — never the store. Set .secret (default
            clickhouse-r2-env) or wire the EnvironmentFile yourself.
          '';
        }
      ];

      # Local working dir = reconstructible cache (R2 holds the durable truth).
      hyper-modern-nixos.state.dirs.clickhouse = {
        path = server.dataDir;
        class = "reconstructible";
      };

      # Self-wire the R2 creds secret (root-owned; clickhouse user reads via env).
      age.secrets = lib.mkIf (server.s3.enable && server.secret != null) {
        ${server.secret}.file = machineSecrets + "/${server.secret}.age";
      };

      # Delegate to the upstream module; our overrides XML carries zookeeper,
      # the cluster, macros, and the S3 storage policy.
      services.clickhouse = {
        enable = true;
        inherit (cfg) package;
      };

      environment.etc."clickhouse-server/config.d/hyper-modern.xml".source = serverConfigFile;

      # allow runningDifference() for grafana dashboard rate queries
      environment.etc."clickhouse-server/users.d/grafana-compat.xml".text = ''
        <clickhouse>
          <profiles>
            <default>
              <allow_deprecated_error_prone_window_functions>1</allow_deprecated_error_prone_window_functions>
            </default>
          </profiles>
        </clickhouse>
      '';

      systemd.services.clickhouse = {
        after = [
          "network-online.target"
          "agenix.service"
        ];
        wants = [ "network-online.target" ];
        restartTriggers = [
          serverConfigFile
        ]
        ++ lib.optional (server.s3.enable && server.secret != null) "/run/agenix/${server.secret}";
        serviceConfig = lib.mkIf (server.s3.enable && server.secret != null) {
          # R2 creds (AWS_*) for the S3 disk — from the agenix env file, never the store.
          EnvironmentFile = "/run/agenix/${server.secret}";
        };
      };

      # HTTP (8123) stays loopback for nginx fronting; native (9000) on tailnet only.
      networking.firewall.interfaces = lib.mkIf server.openTailnet {
        tailscale0.allowedTCPPorts = [ server.ports.native ];
      };
    })
  ];
}
