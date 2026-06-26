# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                // hyper-modern-nixos // checks // otel-ingest
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Proves the Stage-3 ingestion spine end to end, as a single-VM NixOS test:
# ClickHouse (standalone — non-replicated otel tables need no Keeper) + the OTel
# GATEWAY collector (otelcol-contrib) with the clickhouse exporter. We push a
# synthetic OTLP log over OTLP/HTTP and assert it lands in otel.otel_logs.
#
# This is the orthogonal proof to clickhouse-server.nix: that test proved
# server↔Keeper coordination; THIS proves the collector→ClickHouse write path
# (schema auto-creation + the actual row landing). Local disk, single node.
{ pkgs }:
let
  otlpHttpPort = 4318;

  gatewaySettings = {
    receivers.otlp.protocols = {
      http.endpoint = "127.0.0.1:${toString otlpHttpPort}";
    };
    processors.batch = {
      # flush fast so the test doesn't wait on the default 200ms*timeout window
      timeout = "1s";
      send_batch_size = 1;
    };
    exporters.clickhouse = {
      endpoint = "tcp://127.0.0.1:9000?dial_timeout=10s";
      database = "otel";
      username = "default";
      create_schema = true;
      ttl = "720h";
      # Synchronous inserts so a single record is queryable right after the 200.
      async_insert = false;
      logs_table_name = "otel_logs";
      metrics_table_name = "otel_metrics";
      traces_table_name = "otel_traces";
    };
    service.pipelines.logs = {
      receivers = [ "otlp" ];
      processors = [ "batch" ];
      exporters = [ "clickhouse" ];
    };
  };

  # A minimal OTLP/HTTP logs payload (one log record). NOTE: timeUnixNano is
  # injected at RUN TIME (NOW_NS placeholder) — the otel_logs table is
  # `PARTITION BY toDate(Timestamp)` with a 30d TTL, so a hard-coded past
  # timestamp would be inserted and then INSTANTLY TTL-evicted (insert "succeeds",
  # count stays 0). The log body must land with a current timestamp.
  otlpLogTemplate = builtins.toJSON {
    resourceLogs = [
      {
        resource.attributes = [
          {
            key = "host.name";
            value.stringValue = "checkhost";
          }
        ];
        scopeLogs = [
          {
            logRecords = [
              {
                timeUnixNano = "NOW_NS";
                observedTimeUnixNano = "NOW_NS";
                severityText = "INFO";
                body.stringValue = "hyper-modern otel ingest smoke";
              }
            ];
          }
        ];
      }
    ];
  };
  payloadTemplate = pkgs.writeText "otlp-log.json.tmpl" otlpLogTemplate;
in
pkgs.testers.runNixOSTest {
  name = "otel-ingest";

  nodes.machine = { pkgs, ... }: {
    services.clickhouse.enable = true;

    services.opentelemetry-collector = {
      enable = true;
      package = pkgs.opentelemetry-collector-contrib;
      settings = gatewaySettings;
    };

    # Don't let the collector race ClickHouse at boot (create_schema dials :9000).
    systemd.services.opentelemetry-collector = {
      after = [ "clickhouse.service" ];
      requires = [ "clickhouse.service" ];
    };

    environment.systemPackages = [
      pkgs.curl
      pkgs.clickhouse
    ];

    virtualisation.memorySize = 3072;
    virtualisation.diskSize = 6144;
  };

  testScript = ''
    machine.start()

    # ClickHouse + the collector both up.
    machine.wait_for_unit("clickhouse.service")
    machine.wait_for_open_port(9000)
    machine.wait_for_unit("opentelemetry-collector.service")
    machine.wait_for_open_port(${toString otlpHttpPort})

    # Stamp the payload with a CURRENT timestamp at run time (a past timestamp
    # would be TTL-evicted on insert — see the template comment).
    def push():
        machine.succeed(
            "ns=$(date +%s)000000000; "
            "sed \"s/NOW_NS/$ns/g\" ${payloadTemplate} > /tmp/otlp-log.json; "
            "curl -sS -f -X POST -H 'Content-Type: application/json' "
            "--data @/tmp/otlp-log.json http://127.0.0.1:${toString otlpHttpPort}/v1/logs"
        )

    # First push proves the receiver parses + accepts the payload (HTTP 200).
    machine.wait_until_succeeds(
        "ns=$(date +%s)000000000; "
        "sed \"s/NOW_NS/$ns/g\" ${payloadTemplate} > /tmp/otlp-log.json; "
        "curl -sS -f -X POST -H 'Content-Type: application/json' "
        "--data @/tmp/otlp-log.json http://127.0.0.1:${toString otlpHttpPort}/v1/logs"
    )

    # It lands in otel.otel_logs (sync insert; current Timestamp survives the
    # 30d TTL). Re-push each attempt in case the first raced schema creation.
    def landed(_):
        push()
        machine.sleep(2)
        cnt = machine.succeed(
            "clickhouse-client --query \"SELECT count() FROM otel.otel_logs\""
        ).strip()
        return cnt not in ("", "0")

    retry(landed, timeout_seconds=60)

    body = machine.succeed(
        "clickhouse-client --query \"SELECT Body FROM otel.otel_logs ORDER BY Timestamp DESC LIMIT 1\""
    ).strip()
    assert "hyper-modern otel ingest smoke" in body, f"log body not found, got: {body!r}"

    machine.log("OTLP log ingested into ClickHouse via the collector — Stage 3 proven")

    machine.log("OTLP log ingested into ClickHouse via the collector — Stage 3 proven")
  '';
}
