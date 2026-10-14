# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                  // hyper-modern-nixos // nl-az rig // sink
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The Azure soak site's observability sink, ON the site: shannon's single-box
# shape (ClickHouse keeper + server, OTel agent fused with the gateway,
# Grafana) on the rig, so a campaign's telemetry lands beside the campaign
# instead of on a laptop that may be closed. The soak driver itself is
# modules/flake/nativelink/soak/rig.nix (hyper-modern-nixos.soakRig.*).
#
#   nodes ──OTLP 4317 (tailnet)──▶ otelcol ──▶ ClickHouse `otel` ──▶ Grafana :3000
#   soak CLI (lane 2) ──127.0.0.1:8123/9000──▶ ClickHouse `soak`  ──▶ Grafana
#
# Reach: the policy lets nl-soak hit the rig on 4317 only; everything else is
# loopback. Grafana through the bastion:
#   ssh -i ~/.ssh/id_ed25519_b7r6 -N -L 3000:127.0.0.1:3000 b7r6@52.246.254.11
#   → http://127.0.0.1:3000 (anonymous Viewer; admin password in
#     /var/lib/grafana/admin-password on the rig, generated on first start).
#
# Registry coupling, and why nothing here is registry-derived: the rig is on
# the site's own tailnet (tail8ec1af.ts.net), not the fleet's, so the registry
# (osiris-walleye.ts.net names, `ch` / `clickhouse-keeper` tags) describes a
# network this host cannot see. The keeper names itself at 127.0.0.1, the
# server's replica is 127.0.0.1, and the nodes' agents are pointed at the rig
# by name in ./common.nix.
#
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  # The NativeLink dashboard is the FLAKE's (its telemetry contract and its
  # dashboard move together); nixos-config's copy under modules/flake/grafana
  # is the fleet's and is not provisioned here.
  # Every dashboard the flake ships (nativelink, projector, soak-runs) as one
  # directory; Grafana's file provider reads the whole directory.
  nativelinkDashboards = flake.inputs.hypermodern-nativelink.packages.${system}.grafana-dashboards;

  clickhouseNative = "127.0.0.1:${toString config.hyper-modern-nixos.databases.clickhouse.server.ports.native}";

  # ── The `soak` schema: the contract between the driver (lane 2) and the
  # dashboards (lane 3). Declarative: applied idempotently by a oneshot after
  # every ClickHouse start and on every switch that changes it. Plain
  # MergeTree (no Keeper dependency; the sink is one box). No TTL: campaign
  # results are the point of the site and are tiny next to telemetry.
  soakSchema = pkgs.writeText "soak-schema.sql" ''
    CREATE DATABASE IF NOT EXISTS soak;

    CREATE TABLE IF NOT EXISTS soak.runs (
      run_id            String,
      started           DateTime,
      finished          Nullable(DateTime),
      site              String,
      target            String,
      rechaos_rev       String,
      duration_s        UInt32,
      seeds             String,
      kills             UInt32,
      monkey_iterations UInt32,
      findings_total    UInt32,
      unique_signatures UInt32,
      baseline          UInt32,
      oracle_verdict    LowCardinality(String),
      stress_requests   UInt32,
      exit_code         UInt8,
      summary_json      String
    ) ENGINE = MergeTree ORDER BY (started, run_id);

    CREATE TABLE IF NOT EXISTS soak.findings (
      run_id    String,
      ts        DateTime,
      source    LowCardinality(String),
      signature String,
      kind      String,
      evidence  String,
      baseline  UInt8
    ) ENGINE = MergeTree ORDER BY (run_id, ts, signature);

    CREATE TABLE IF NOT EXISTS soak.kills (
      run_id String,
      ts     DateTime,
      target String,
      action String,
      ok     UInt8
    ) ENGINE = MergeTree ORDER BY (run_id, ts);

    CREATE TABLE IF NOT EXISTS soak.events (
      run_id  String,
      ts      DateTime,
      phase   LowCardinality(String),
      message String
    ) ENGINE = MergeTree ORDER BY (run_id, ts);
  '';
  wall = config.hyper-modern-nixos.soakSink.wall;

  # ── The wall: one site's Grafana reads another site's sink ─────────────────
  # The reader is ClickHouse's own `grafana` user: SELECT on soak.* and otel.*
  # and nothing else, readonly=2 (Grafana sets per-query settings), reachable
  # only from the tailnet's CGNAT range. No password, on purpose: reach is
  # already the host firewall (8123 on tailscale0 only), the tailnet policy
  # (exactly one rule, viewer rig → source rig:8123, see the flake's
  # netops/policy.dhall `walls`) and this network clause; a password would be
  # a third secret shared across two sites' trees, sent over WireGuard, that
  # buys nothing those three do not. The `default` user, which the soak CLI
  # and the OTel exporter use over loopback, is pinned to loopback so binding
  # the server to every interface exposes nothing passwordless.
  wallUsers = pkgs.writeText "clickhouse-wall-users.xml" ''
    <clickhouse>
      <profiles>
        <wall_reader>
          <readonly>2</readonly>
          <max_execution_time>60</max_execution_time>
          <allow_deprecated_error_prone_window_functions>1</allow_deprecated_error_prone_window_functions>
        </wall_reader>
      </profiles>
      <users>
        <default>
          <networks replace="replace">
            <ip>127.0.0.1</ip>
            <ip>::1</ip>
          </networks>
        </default>
        <grafana>
          <no_password/>
          <networks>
            <ip>100.64.0.0/10</ip>
            <ip>fd7a:115c:a1e0::/48</ip>
          </networks>
          <profile>wall_reader</profile>
          <quota>default</quota>
          <grants>
            <query>GRANT SELECT ON soak.*</query>
            <query>GRANT SELECT ON otel.*</query>
          </grants>
        </grafana>
      </users>
    </clickhouse>
  '';

  peerDatasource = p: {
    name = "ClickHouse ${p.name}";
    type = "grafana-clickhouse-datasource";
    uid = "clickhouse-${p.name}";
    access = "proxy";
    isDefault = false;
    jsonData = {
      host = p.host;
      port = 8123;
      protocol = "http";
      defaultDatabase = "otel";
      username = "grafana";
    };
  };
in
{
  options.hyper-modern-nixos.soakSink.wall = {
    serve = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Serve this rig's ClickHouse read-only to the tailnet: HTTP 8123 on
        tailscale0, user `grafana` (SELECT on soak.* and otel.*), so another
        site's Grafana can put this site beside its own on one wall. Reach is
        the tailnet policy's `walls` relation.
      '';
    };
    peers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              example = "az2";
              description = "The peer site's name; the datasource uid is clickhouse-<name>.";
            };
            host = lib.mkOption {
              type = lib.types.str;
              example = "nl-az2-rig.tail8ec1af.ts.net";
              description = "The peer rig's MagicDNS name on the soak tailnet.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Other sites' rigs this rig's Grafana reads (each one a `serve = true`
        rig): one extra ClickHouse datasource per peer, uid `clickhouse-<name>`,
        which the differential dashboard (`nl-differential`) and the `site`
        variable of the projector bind to.
      '';
    };
  };

  config = {
    # ── ClickHouse: keeper + server, one box, local disk ───────────────────────
    # Keeper is coordination theater on one node (allowSolo) but keeps the
    # server's config the fleet's; the S3→R2 tier is OFF — the rig's disk is the
    # store, retention is the TTL below, and campaign artifacts are what restic
    # ships off-box, not telemetry.
    hyper-modern-nixos.databases.clickhouse = {
      keeper = {
        enable = true;
        allowSolo = true;
        members = [
          {
            physical = config.networking.hostName;
            address = "127.0.0.1";
          }
        ];
        forceSync = true; # one node: the disk IS the durability
        openTailnet = false; # nobody on the tailnet dials the keeper
      };
      server = {
        enable = true;
        replicaHost = "127.0.0.1";
        openTailnet = false; # 9000 is loopback-only: the policy admits only 4317 anyway
        # A wall source binds every interface (ClickHouse cannot bind an
        # interface by name); the host firewall admits 8123 on tailscale0 only.
        listenHost = if wall.serve then "::" else "127.0.0.1";
        s3.enable = false;
        secret = null;
      };
    };

    # The rig also runs rechaos + the chaos monkey; ClickHouse does not get the
    # machine. Half of 16 GiB is plenty for a sink of this size.
    environment.etc."clickhouse-server/config.d/soak-rig.xml".text = ''
      <clickhouse>
        <max_server_memory_usage_to_ram_ratio>0.5</max_server_memory_usage_to_ram_ratio>
      </clickhouse>
    '';

    environment.etc."clickhouse-server/users.d/wall.xml" = lib.mkIf wall.serve { source = wallUsers; };
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = lib.mkIf wall.serve [ 8123 ];

    systemd.services.clickhouse-soak-schema = {
      description = "ClickHouse: the soak.* schema (declarative, idempotent)";
      after = [ "clickhouse.service" ];
      requires = [ "clickhouse.service" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ soakSchema ];
      path = [ config.hyper-modern-nixos.databases.clickhouse.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # Type=notify readiness precedes the native port by a beat on a cold boot;
      # poll it rather than race it.
      script = ''
        for _ in $(seq 1 60); do
          if clickhouse-client --host 127.0.0.1 --query 'SELECT 1' >/dev/null 2>&1; then
            exec clickhouse-client --host 127.0.0.1 --multiquery --queries-file ${soakSchema}
          fi
          sleep 2
        done
        echo "clickhouse never answered on ${clickhouseNative}" >&2
        exit 1
      '';
    };

    # ── OTel: agent fused with the gateway ─────────────────────────────────────
    # Gateway: OTLP/gRPC on 0.0.0.0:4317 (the module opens it on tailscale0
    # only; the policy narrows that to the nodes), ClickHouse exporter owning
    # the `otel` schema. Agent: this box's own hostmetrics + whole journal (the
    # campaigns are transient systemd-run units, so no unit filter would catch
    # them) + ClickHouse's own /metrics.
    hyper-modern-nixos.observability.otel = {
      agent = {
        enable = true;
        scrapeTargets = [
          "127.0.0.1:9363" # clickhouse
          "127.0.0.1:9364" # clickhouse-keeper
        ];
      };
      gateway = {
        enable = true;
        # 128 GiB disk, ~10k nativelink series per node every 30 s: two weeks.
        clickhouse.ttl = "336h";
      };
    };

    # Fewer, larger inserts: MergeTree wants parts, not a part per 200 ms batch
    # from four agents. 5 s of fleet telemetry is a sane part.
    services.opentelemetry-collector.settings.processors.batch = {
      timeout = "5s";
      send_batch_size = 8192;
      send_batch_max_size = 16384;
    };

    # ── Grafana: loopback, through the bastion ─────────────────────────────────
    # No edge, no IdP: :3000 on 127.0.0.1, reached with ssh -L (header). Viewers
    # are anonymous so the projector just works; edits need the admin password
    # the first start minted into the state dir (nothing secret in the store,
    # nothing to rekey in the fleet's agenix tree for a transient site).
    services.grafana = {
      enable = true;

      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = 3000;
          root_url = "http://127.0.0.1:3000/";
          domain = "127.0.0.1";
        };

        security = {
          admin_user = "admin";
          admin_password = "$__file{/var/lib/grafana/admin-password}";
          secret_key = "$__file{/var/lib/grafana/admin-password}";
        };

        "auth.anonymous" = {
          enabled = true;
          org_role = "Viewer";
        };
        analytics.reporting_enabled = false;
      };

      declarativePlugins = [ pkgs.grafanaPlugins.grafana-clickhouse-datasource ];

      provision = {
        enable = true;

        # One datasource covers both databases: `otel` is the default, `soak.*`
        # is addressed fully qualified. Each wall peer is a second one.
        datasources.settings.datasources = [
          {
            name = "ClickHouse";
            type = "grafana-clickhouse-datasource";
            uid = "clickhouse";
            access = "proxy";
            isDefault = true;
            jsonData = {
              host = "127.0.0.1";
              port = config.hyper-modern-nixos.databases.clickhouse.server.ports.native;
              protocol = "native";
              defaultDatabase = "otel";
              username = "default";
            };
          }
        ]
        ++ map peerDatasource wall.peers;

        dashboards.settings.providers = [
          {
            name = "soak";
            type = "file";
            options.path = "/etc/grafana/dashboards";
            options.foldersFromFilesStructure = true;
          }
        ];
      };
    };

    # Runs as the grafana user (no `+`), so the state dir is writable and the
    # file is the user's own. Idempotent: only minted when absent.
    systemd.services.grafana.preStart = ''
      f=/var/lib/grafana/admin-password
      if [ ! -s "$f" ]; then
        (umask 077; ${pkgs.coreutils}/bin/head -c 24 /dev/urandom | ${pkgs.coreutils}/bin/base64 | ${pkgs.coreutils}/bin/tr -d '\n=/+' > "$f")
      fi
    '';

    environment.etc."grafana/dashboards".source = nativelinkDashboards;
  };
}
