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
          static_configs = [
            { targets = agent.scrapeTargets; }
          ];
        }
      ];
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

  procChain =
    lib.optionals isAgent [ "resourcedetection" ]
    ++ lib.optionals (isAgent && !isGateway) [ "resource" ]
    ++ [ "batch" ];

  # receiver lists per signal
  baseReceivers = lib.optional (receivers ? otlp) "otlp";
  metricReceivers =
    baseReceivers
    ++ lib.optional isAgent "hostmetrics"
    ++ lib.optional (isAgent && agent.scrapeTargets != [ ]) "prometheus";
  logReceivers = baseReceivers ++ lib.optional isAgent "journald";
  traceReceivers = baseReceivers;

  mkPipeline = recv: {
    receivers = recv;
    processors = procChain;
    exporters = [ exporterName ];
  };

  otelSettings = {
    inherit receivers processors exporters;
    service.pipelines = {
      metrics = mkPipeline metricReceivers;
      logs = mkPipeline logReceivers;
      traces = mkPipeline traceReceivers;
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

    # journald receiver needs the collector in the systemd-journal group.
    systemd.services.opentelemetry-collector.serviceConfig = lib.mkIf isAgent {
      SupplementaryGroups = [ "systemd-journal" ];
    };

    # Gateway OTLP listener exposed on the tailnet only.
    networking.firewall.interfaces = lib.mkIf (isGateway && gateway.openTailnet) {
      tailscale0.allowedTCPPorts = [ gateway.otlpPort ];
    };
  };
}
