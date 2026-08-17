# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                       // hyper-modern-nixos // observability
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The OpenTelemetry ingestion spine, OFF BY DEFAULT, under
# hyper-modern-nixos.observability.otel. The single pipeline for the three
# pillars (logs + metrics + traces), replacing the scrape/forward model with one
# OTLP spine. See docs/infrastructure/clickhouse.md (Stage 3).
#
# Two roles (a host can run either; the gateway node typically runs both):
#
#   - agent   — runs on every fleet node. Collects host metrics (hostmetrics)
#               and journald logs, accepts local app OTLP, and exports via OTLP
#               to the gateway over the tailnet. Lightweight.
#   - gateway — runs beside ClickHouse (watchtower). Accepts OTLP from the
#               agents and writes logs/metrics/traces into ClickHouse via the
#               `clickhouse` exporter (it owns schema creation). The data lands
#               in the same store the server (Stage 2) manages.
#
# Both delegate to the upstream `services.opentelemetry-collector` module
# (otelcol-contrib): we author the pipeline as `settings` (YAML), it renders +
# validates + runs it. otelcol-contrib 0.151 ships the clickhouse exporter and
# the journald/hostmetrics/otlp receivers we need.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.observability.otel;
  topo = config.hyper-modern-nixos.topology;

  inherit (cfg) agent gateway;

  # The gateway's OTLP endpoint, derived from the topology registry: the host
  # tagged `clickhouse` (the ClickHouse server / observability sink).
  clickhouseHosts = lib.attrValues (topo.helpers.hostsWithService "ch");
  gatewayHost = if clickhouseHosts == [ ] then null else (lib.head clickhouseHosts);
  gatewayFqdn =
    if gatewayHost == null then null else "${gatewayHost.tailnet}.${topo.registry.tailnetSuffix}";

  # A host can be agent, gateway, or both. The upstream module runs ONE
  # collector, so when both roles are active on one node we fuse them into a
  # single pipeline: local collection (hostmetrics/journald) lands DIRECTLY in
  # the clickhouse exporter (no OTLP self-hop), while OTLP-in still receives the
  # remote agents. So:
  #   - exporter is `clickhouse` when this node is the gateway, else `otlp`
  #     (ship to the remote gateway);
  #   - receivers include local collection when this node is the agent, and the
  #     OTLP listener when it's the gateway (or the local app-OTLP when agent).

  isGateway = gateway.enable;
  isAgent = agent.enable;

  # ── receivers ──
  hostmetrics = {
    collection_interval = "30s";
    scrapers = {
      cpu = { };
      load = { };
      memory = { };
      disk = { };
      filesystem = { };
      network = { };
      paging = { };
    };
  };

  receivers =
    # local app OTLP (agent: loopback) and/or the gateway OTLP listener (tailnet).
    lib.optionalAttrs (isAgent && !isGateway) {
      otlp.protocols.grpc.endpoint = "127.0.0.1:${toString agent.localOtlpPort}";
    }
    // lib.optionalAttrs isGateway {
      otlp.protocols.grpc.endpoint = "0.0.0.0:${toString gateway.otlpPort}";
    }
    // lib.optionalAttrs isAgent {
      inherit hostmetrics;
      journald.units = agent.journaldUnits;
    }
    // lib.optionalAttrs (isAgent && agent.scrapeTargets != [ ]) {
      prometheus.config.scrape_configs = [
        {
          job_name = "fleet-services";
          scrape_interval = "30s";
          static_configs = [ { targets = agent.scrapeTargets; } ];
        }
      ];
    }
    // lib.optionalAttrs (isAgent && agent.logPaths != [ ]) {
      filelog = {
        include = agent.logPaths;
        start_at = "end";
        operators = [
          {
            type = "regex_parser";
            id = "pgbackrest_parser";
            regex = "^(?P<timestamp>\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2})\\S*\\s+P\\d+\\s+(?P<level>\\w+):\\s+(?P<message>.*)$";
            on_error = "send";
            timestamp = {
              parse_from = "attributes.timestamp";
              layout = "%Y-%m-%d %H:%M:%S";
            };
            severity = {
              parse_from = "attributes.level";
            };
          }
        ];
      };
    };

  # ── exporters: clickhouse on the gateway node, else otlp to the remote gateway ──
  chEndpoint = "tcp://127.0.0.1:${toString gateway.clickhouse.port}?dial_timeout=10s";
  exporters =
    if isGateway then
      {
        clickhouse = {
          endpoint = chEndpoint;
          database = gateway.clickhouse.database;
          username = gateway.clickhouse.username;
          create_schema = gateway.clickhouse.createSchema;
          ttl = gateway.clickhouse.ttl;
          async_insert = gateway.clickhouse.asyncInsert;
          logs_table_name = "otel_logs";
          metrics_table_name = "otel_metrics";
          traces_table_name = "otel_traces";
        };
      }
    else
      {
        otlp = {
          endpoint = agent.gatewayEndpoint;
          tls.insecure = true; # plaintext over the encrypted tailnet
        };
      };

  exporterName = if isGateway then "clickhouse" else "otlp";

  # ── processors: batch always; stamp host.name on agent-only nodes ──
  # resourcedetection (reads OS hostname) is safe everywhere.
  # the `resource` processor (hardcodes a hostname via upsert) is ONLY for
  # agent-only nodes — on the gateway it would overwrite remote agents' names.
  processors = {
    batch = { };
  }
  // lib.optionalAttrs isAgent {
    resourcedetection = {
      detectors = [ "system" ];
      system.hostname_sources = [ "os" ];
    };
  }
  // lib.optionalAttrs (isAgent && !isGateway) {
    "resource".attributes = [
      {
        key = "host.name";
        value = config.networking.hostName;
        action = "upsert";
      }
    ];
  };

  # processor chains: local collection stamps host.name; gateway pass-through does NOT.
  localProcChain =
    lib.optionals isAgent [ "resourcedetection" ]
    ++ lib.optionals (isAgent && !isGateway) [ "resource" ]
    ++ [ "batch" ];

  # gateway pass-through: only batch (preserve remote agents' host.name)
  gatewayProcChain = [ "batch" ];

  # receiver lists per signal
  localMetricReceivers =
    lib.optional isAgent "hostmetrics"
    ++ lib.optional (isAgent && agent.scrapeTargets != [ ]) "prometheus";
  localLogReceivers =
    lib.optional isAgent "journald" ++ lib.optional (isAgent && agent.logPaths != [ ]) "filelog";

  # on a fused gateway+agent node, split pipelines:
  #   - metrics/local: hostmetrics + prometheus → resourcedetection → batch → exporter
  #   - metrics/gateway: otlp → batch → exporter (no resourcedetection)
  #   - logs/local: journald → resourcedetection → batch → exporter
  #   - logs/gateway: otlp → batch → exporter
  # on a pure agent: single pipeline with otlp + local receivers → full procChain → exporter
  # on a pure gateway (no agent): single pipeline with otlp → batch → exporter
  otelSettings = {
    inherit receivers processors exporters;
    service.pipelines =
      if isGateway && isAgent then
        {
          # fused node: separate local vs gateway pipelines
          "metrics/local" = {
            receivers = localMetricReceivers;
            processors = localProcChain;
            exporters = [ exporterName ];
          };
          "metrics/gateway" = {
            receivers = [ "otlp" ];
            processors = gatewayProcChain;
            exporters = [ exporterName ];
          };
          "logs/local" = {
            receivers = localLogReceivers;
            processors = localProcChain;
            exporters = [ exporterName ];
          };
          "logs/gateway" = {
            receivers = [ "otlp" ];
            processors = gatewayProcChain;
            exporters = [ exporterName ];
          };
          traces = {
            receivers = [ "otlp" ];
            processors = gatewayProcChain;
            exporters = [ exporterName ];
          };
        }
      else if isGateway then
        {
          # pure gateway
          metrics = {
            receivers = [ "otlp" ];
            processors = gatewayProcChain;
            exporters = [ exporterName ];
          };
          logs = {
            receivers = [ "otlp" ];
            processors = gatewayProcChain;
            exporters = [ exporterName ];
          };
          traces = {
            receivers = [ "otlp" ];
            processors = gatewayProcChain;
            exporters = [ exporterName ];
          };
        }
      else
        {
          # pure agent: all receivers in one pipeline, full procChain
          metrics = {
            receivers = [ "otlp" ] ++ localMetricReceivers;
            processors = localProcChain;
            exporters = [ exporterName ];
          };
          logs = {
            receivers = [ "otlp" ] ++ localLogReceivers;
            processors = localProcChain;
            exporters = [ exporterName ];
          };
          traces = {
            receivers = [ "otlp" ];
            processors = localProcChain;
            exporters = [ exporterName ];
          };
        };
  };
in
{
  options.hyper-modern-nixos.observability.otel = {
    agent = {
      enable = lib.mkEnableOption "OpenTelemetry collector AGENT (host metrics + journald → gateway)";

      gatewayEndpoint = lib.mkOption {
        type = lib.types.str;
        default = if gatewayFqdn == null then "" else "${gatewayFqdn}:4317";
        defaultText = "<clickhouse-host>.<tailnetSuffix>:4317 (from the registry)";
        description = ''
          OTLP/gRPC endpoint of the gateway collector. Defaults to the
          registry's `clickhouse`-tagged host on the gateway OTLP port.
        '';
      };

      localOtlpPort = lib.mkOption {
        type = lib.types.port;
        default = 4319;
        description = "Local OTLP/gRPC port apps push to (loopback only).";
      };

      journaldUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "systemd units to tail into logs ([] = the whole journal).";
      };

      scrapeTargets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "127.0.0.1:9153"
          "127.0.0.1:3001"
        ];
        description = ''
          Prometheus scrape targets (host:port). Each is scraped at /metrics every 30s.
          Set per-host to match which services run there.
        '';
      };

      logPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "/var/log/pgbackrest/*.log" ];
        description = ''
          File paths (glob patterns) to tail via the filelog receiver. Each matched
          file is tailed continuously. Use for services that write log files instead
          of (or in addition to) journald.
        '';
      };
    };

    gateway = {
      enable = lib.mkEnableOption "OpenTelemetry collector GATEWAY (OTLP → ClickHouse exporter)";

      otlpPort = lib.mkOption {
        type = lib.types.port;
        default = 4317;
        description = "OTLP/gRPC port agents push to (opened on tailscale0).";
      };

      openTailnet = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Open the gateway OTLP port on tailscale0 only.";
      };

      clickhouse = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 9000;
          description = "ClickHouse native port the exporter writes to (loopback).";
        };
        database = lib.mkOption {
          type = lib.types.str;
          default = "otel";
          description = "ClickHouse database for the OTLP tables.";
        };
        username = lib.mkOption {
          type = lib.types.str;
          default = "default";
          description = "ClickHouse user the exporter connects as.";
        };
        createSchema = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Let the exporter create its MergeTree tables on startup.";
        };
        asyncInsert = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            ClickHouse async_insert for the exporter. Default false (synchronous):
            telemetry is queryable immediately after insert, which is what you want
            for an observability sink ("did my data land"). Set true to trade
            immediate queryability for higher insert throughput at scale.
          '';
        };
        ttl = lib.mkOption {
          type = lib.types.str;
          default = "720h"; # 30 days
          description = "MergeTree TTL for the OTLP tables (retention).";
        };
      };
    };
  };

  # One collector per host, settings fused from the active role(s) above.
  config = lib.mkIf (isAgent || isGateway) {
    assertions = [
      {
        # An agent that isn't also the local gateway must know where to ship.
        assertion = isGateway || (agent.gatewayEndpoint != "");
        message = ''
          observability.otel.agent is enabled but no gateway endpoint resolved:
          no host is tagged `clickhouse` in the topology registry. Tag the
          gateway host + re-render, or set agent.gatewayEndpoint explicitly.
        '';
      }
    ];

    services.opentelemetry-collector = {
      enable = true;
      package = pkgs.opentelemetry-collector-contrib;
      settings = otelSettings;
    };

    systemd.services.opentelemetry-collector = lib.mkMerge [
      # journald receiver needs systemd-journal group; filelog needs access to
      # service log dirs (e.g. pgbackrest owned by supabase-postgres).
      (lib.mkIf isAgent {
        serviceConfig = {
          SupplementaryGroups = [
            "systemd-journal"
          ]
          ++ lib.optional (agent.logPaths != [ ]) "supabase-postgres";
          ReadOnlyPaths = agent.logPaths;
        };
      })

      # The gateway exporter creates/verifies its ClickHouse schema at startup.
      # Order it after ClickHouse's Type=notify readiness and retry forever if
      # the database is unavailable, so a cold boot converges without operator
      # intervention instead of exhausting systemd's default 5-in-10s limit.
      (lib.mkIf isGateway {
        after = [ "clickhouse.service" ];
        wants = [ "clickhouse.service" ];
        startLimitIntervalSec = 0;
        serviceConfig.RestartSec = "5s";
      })
    ];

    # Gateway OTLP listener exposed on the tailnet only.
    networking.firewall.interfaces = lib.mkIf (isGateway && gateway.openTailnet) {
      tailscale0.allowedTCPPorts = [ gateway.otlpPort ];
    };
  };
}
