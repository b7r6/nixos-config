# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hypermodern // grafana // dashboards
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# all grafana dashboards as nix attrsets. Rendered to JSON via builtins.toJSON
# and deployed to /etc/grafana/dashboards/ by the file provisioner.
let
  ds = {
    type = "grafana-clickhouse-datasource";
    uid = "clickhouse";
  };

  # shorthand panel constructor
  panel =
    {
      id,
      title,
      type ? "timeseries",
      x ? 0,
      y ? 0,
      w ? 12,
      h ? 8,
      unit ? "short",
      sql,
      format ? 1,
    }:
    {
      inherit id title type;
      gridPos = {
        inherit
          x
          y
          w
          h
          ;
      };
      datasource = ds;
      fieldConfig.defaults.unit = unit;
      targets = [
        {
          rawSql = sql;
          inherit format;
          queryType = "sql";
          refId = "A";
        }
      ];
    };

  # common time filter
  tf = "$__timeFilter(TimeUnix)";
  tfLog = "$__timeFilter(Timestamp)";
  host = "ResourceAttributes['host.name']";
in
{
  # ════════════════════════════════════════════════════════════════════════════════
  #  1. Fleet Overview (the battle station)
  # ════════════════════════════════════════════════════════════════════════════════
  fleet-overview = {
    title = "Fleet Overview";
    uid = "fleet-overview";
    schemaVersion = 39;
    refresh = "30s";
    time = {
      from = "now-1h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "fleet"
      "overview"
    ];
    templating.list = [
      {
        name = "host";
        label = "Host";
        type = "query";
        datasource = ds;
        query = "SELECT DISTINCT ${host} FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 1 HOUR";
        multi = false;
        includeAll = true;
      }
    ];
    panels = [
      (panel {
        id = 1;
        title = "Load average (1m)";
        x = 0;
        y = 0;
        w = 8;
        unit = "short";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'system.cpu.load_average.1m' AND ${tf} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 2;
        title = "Memory usage";
        x = 8;
        y = 0;
        w = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.memory.usage' AND Attributes['state'] = 'used' AND ${tf} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 3;
        title = "Disk I/O";
        x = 16;
        y = 0;
        w = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.disk.io' AND ${tf} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 4;
        title = "Network I/O";
        x = 0;
        y = 8;
        w = 12;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND ${tf} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 5;
        title = "Filesystem usage";
        x = 12;
        y = 8;
        w = 12;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, ${host} as host, Attributes['device'] as dev, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.filesystem.usage' AND Attributes['state'] = 'used' AND ${tf} GROUP BY time, host, dev ORDER BY time";
      })
      (panel {
        id = 6;
        title = "CoreDNS queries/sec";
        x = 0;
        y = 16;
        w = 8;
        unit = "ops";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 7;
        title = "DNS cache hit rate";
        x = 8;
        y = 16;
        w = 8;
        unit = "percentunit";
        sql = "SELECT TimeUnix as time, avg(hits.Value) / (avg(hits.Value) + avg(misses.Value)) as value FROM otel.otel_metrics_sum hits JOIN otel.otel_metrics_sum misses ON hits.TimeUnix = misses.TimeUnix WHERE hits.MetricName = 'coredns_cache_hits_total' AND misses.MetricName = 'coredns_cache_misses_total' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 8;
        title = "PostgREST JWT cache";
        x = 16;
        y = 16;
        w = 8;
        unit = "ops";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName IN ('pgrst_jwt_cache_hits_total', 'pgrst_jwt_cache_requests_total') AND ${tf} GROUP BY time, MetricName ORDER BY time";
      })
      (panel {
        id = 9;
        title = "Errors (last hour)";
        x = 0;
        y = 24;
        w = 24;
        h = 10;
        type = "table";
        format = 2;
        sql = "SELECT Timestamp, ${host} as host, SeverityText as level, substring(Body, 1, 200) as message FROM otel.otel_logs WHERE SeverityNumber >= 17 AND ${tfLog} ORDER BY Timestamp DESC LIMIT 100";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  2. Per-Host Drill-Down
  # ════════════════════════════════════════════════════════════════════════════════
  host-drilldown = {
    title = "Host Drill-Down";
    uid = "host-drilldown";
    schemaVersion = 39;
    refresh = "30s";
    time = {
      from = "now-1h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "fleet"
      "host"
    ];
    templating.list = [
      {
        name = "host";
        label = "Host";
        type = "query";
        datasource = ds;
        query = "SELECT DISTINCT ${host} FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 1 HOUR";
        multi = false;
        includeAll = false;
      }
    ];
    panels = [
      (panel {
        id = 1;
        title = "CPU time by state";
        x = 0;
        y = 0;
        w = 12;
        unit = "s";
        sql = "SELECT TimeUnix as time, Attributes['state'] as state, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.cpu.time' AND ${host} = '$host' AND ${tf} GROUP BY time, state ORDER BY time";
      })
      (panel {
        id = 2;
        title = "Memory by state";
        x = 12;
        y = 0;
        w = 12;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, Attributes['state'] as state, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.memory.usage' AND ${host} = '$host' AND ${tf} GROUP BY time, state ORDER BY time";
      })
      (panel {
        id = 3;
        title = "Disk I/O by device";
        x = 0;
        y = 8;
        w = 12;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, Attributes['device'] as device, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.disk.io' AND ${host} = '$host' AND ${tf} GROUP BY time, device ORDER BY time";
      })
      (panel {
        id = 4;
        title = "Network by interface";
        x = 12;
        y = 8;
        w = 12;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, Attributes['device'] as iface, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND ${host} = '$host' AND ${tf} GROUP BY time, iface ORDER BY time";
      })
      (panel {
        id = 5;
        title = "Filesystem usage by mount";
        x = 0;
        y = 16;
        w = 12;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, Attributes['mountpoint'] as mount, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.filesystem.usage' AND Attributes['state'] = 'used' AND ${host} = '$host' AND ${tf} GROUP BY time, mount ORDER BY time";
      })
      (panel {
        id = 6;
        title = "Load averages";
        x = 12;
        y = 16;
        w = 12;
        unit = "short";
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName LIKE 'system.cpu.load_average%' AND ${host} = '$host' AND ${tf} GROUP BY time, metric ORDER BY time";
      })
      (panel {
        id = 7;
        title = "Recent logs";
        x = 0;
        y = 24;
        w = 24;
        h = 12;
        type = "logs";
        format = 2;
        sql = "SELECT Timestamp as time, Body as content, SeverityText as level FROM otel.otel_logs WHERE ${host} = '$host' AND ${tfLog} ORDER BY Timestamp DESC LIMIT 500";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  3. ClickHouse Internals
  # ════════════════════════════════════════════════════════════════════════════════
  clickhouse-internals = {
    title = "ClickHouse Internals";
    uid = "clickhouse-internals";
    schemaVersion = 39;
    refresh = "30s";
    time = {
      from = "now-1h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "clickhouse"
      "internals"
    ];
    panels = [
      (panel {
        id = 1;
        title = "Queries running";
        x = 0;
        y = 0;
        w = 8;
        unit = "short";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_Query' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 2;
        title = "Memory usage";
        x = 8;
        y = 0;
        w = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_TotalBytesOfMergeTreeTables' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 3;
        title = "Parts count";
        x = 16;
        y = 0;
        w = 8;
        unit = "short";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_NumberOfTables' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 4;
        title = "Merges running";
        x = 0;
        y = 8;
        w = 8;
        unit = "short";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_Merge' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 5;
        title = "Insert rows/sec";
        x = 8;
        y = 8;
        w = 8;
        unit = "ops";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_InsertedRows' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 6;
        title = "S3 read/write bytes";
        x = 16;
        y = 8;
        w = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, MetricName, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName IN ('ClickHouseProfileEvents_S3ReadBytes', 'ClickHouseProfileEvents_S3WriteBytes') AND ${tf} GROUP BY time, MetricName ORDER BY time";
      })
      (panel {
        id = 7;
        title = "Connections";
        x = 0;
        y = 16;
        w = 12;
        unit = "short";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('ClickHouseMetrics_TCPConnection', 'ClickHouseMetrics_HTTPConnection') AND ${tf} GROUP BY time, MetricName ORDER BY time";
      })
      (panel {
        id = 8;
        title = "Replication queue";
        x = 12;
        y = 16;
        w = 12;
        unit = "short";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_ReplicatedSend' AND ${tf} GROUP BY time ORDER BY time";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  4. Log Explorer
  # ════════════════════════════════════════════════════════════════════════════════
  log-explorer = {
    title = "Log Explorer";
    uid = "log-explorer";
    schemaVersion = 39;
    refresh = "30s";
    time = {
      from = "now-1h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [ "logs" ];
    templating.list = [
      {
        name = "host";
        label = "Host";
        type = "query";
        datasource = ds;
        query = "SELECT DISTINCT ${host} FROM otel.otel_logs WHERE ${tfLog}";
        multi = false;
        includeAll = true;
      }
      {
        name = "search";
        label = "Search";
        type = "textbox";
        query = "";
        multi = false;
        includeAll = false;
      }
    ];
    panels = [
      (panel {
        id = 1;
        title = "Log volume by severity";
        x = 0;
        y = 0;
        w = 24;
        h = 6;
        type = "timeseries";
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, SeverityText as severity, count() as value FROM otel.otel_logs WHERE ${tfLog} AND ($host = '' OR ${host} = '$host') GROUP BY time, severity ORDER BY time";
      })
      (panel {
        id = 2;
        title = "Error count by host";
        x = 0;
        y = 6;
        w = 12;
        h = 6;
        type = "bargauge";
        format = 2;
        unit = "short";
        sql = "SELECT ${host} as host, count() as errors FROM otel.otel_logs WHERE SeverityNumber >= 17 AND ${tfLog} GROUP BY host ORDER BY errors DESC";
      })
      (panel {
        id = 3;
        title = "Top error messages";
        x = 12;
        y = 6;
        w = 12;
        h = 6;
        type = "table";
        format = 2;
        sql = "SELECT substring(Body, 1, 120) as message, count() as occurrences FROM otel.otel_logs WHERE SeverityNumber >= 17 AND ${tfLog} GROUP BY message ORDER BY occurrences DESC LIMIT 20";
      })
      (panel {
        id = 4;
        title = "Full log stream";
        x = 0;
        y = 12;
        w = 24;
        h = 14;
        type = "table";
        format = 2;
        sql = "SELECT Timestamp, ${host} as host, SeverityText as level, Body as message FROM otel.otel_logs WHERE ${tfLog} AND ($host = '' OR ${host} = '$host') AND ($search = '' OR Body LIKE '%$search%') ORDER BY Timestamp DESC LIMIT 500";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  5. Service Health Matrix
  # ════════════════════════════════════════════════════════════════════════════════
  service-health = {
    title = "Service Health";
    uid = "service-health";
    schemaVersion = 39;
    refresh = "30s";
    time = {
      from = "now-5m";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "fleet"
      "health"
    ];
    panels = [
      (panel {
        id = 1;
        title = "Hosts reporting (last 5m)";
        x = 0;
        y = 0;
        w = 8;
        h = 6;
        type = "stat";
        format = 2;
        unit = "short";
        sql = "SELECT uniq(${host}) as hosts FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 5 MINUTE";
      })
      (panel {
        id = 2;
        title = "Total log errors (last 5m)";
        x = 8;
        y = 0;
        w = 8;
        h = 6;
        type = "stat";
        format = 2;
        unit = "short";
        sql = "SELECT count() as errors FROM otel.otel_logs WHERE SeverityNumber >= 17 AND Timestamp > now() - INTERVAL 5 MINUTE";
      })
      (panel {
        id = 3;
        title = "OTel data points/min";
        x = 16;
        y = 0;
        w = 8;
        h = 6;
        type = "stat";
        format = 2;
        unit = "short";
        sql = "SELECT count() / 5 as points_per_min FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 5 MINUTE";
      })
      (panel {
        id = 4;
        title = "Host last-seen";
        x = 0;
        y = 6;
        w = 24;
        h = 8;
        type = "table";
        format = 2;
        sql = "SELECT ${host} as host, max(TimeUnix) as last_seen, dateDiff('second', max(TimeUnix), now()) as seconds_ago, if(dateDiff('second', max(TimeUnix), now()) < 120, 'UP', 'DOWN') as status FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 10 MINUTE GROUP BY host ORDER BY host";
      })
      (panel {
        id = 5;
        title = "Service errors (last hour)";
        x = 0;
        y = 14;
        w = 24;
        h = 8;
        type = "table";
        format = 2;
        sql = "SELECT ${host} as host, JSONExtractString(Body, '_SYSTEMD_UNIT') as unit, count() as errors FROM otel.otel_logs WHERE SeverityNumber >= 17 AND ${tfLog} AND Body LIKE '%_SYSTEMD_UNIT%' GROUP BY host, unit ORDER BY errors DESC LIMIT 30";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  6. Network Topology
  # ════════════════════════════════════════════════════════════════════════════════
  network-topology = {
    title = "Network Topology";
    uid = "network-topology";
    schemaVersion = 39;
    refresh = "30s";
    time = {
      from = "now-1h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "fleet"
      "network"
    ];
    panels = [
      (panel {
        id = 1;
        title = "Network TX by host";
        x = 0;
        y = 0;
        w = 12;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND Attributes['direction'] = 'transmit' AND ${tf} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 2;
        title = "Network RX by host";
        x = 12;
        y = 0;
        w = 12;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND Attributes['direction'] = 'receive' AND ${tf} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 3;
        title = "Network errors";
        x = 0;
        y = 8;
        w = 12;
        unit = "short";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.errors' AND ${tf} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 4;
        title = "Network dropped";
        x = 12;
        y = 8;
        w = 12;
        unit = "short";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.dropped' AND ${tf} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 5;
        title = "Active connections by host";
        x = 0;
        y = 16;
        w = 24;
        h = 8;
        type = "timeseries";
        unit = "short";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.connections' AND ${tf} GROUP BY time, host ORDER BY time";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  7. Forgejo Activity (from logs — no native prometheus yet)
  # ════════════════════════════════════════════════════════════════════════════════
  forgejo-activity = {
    title = "Forgejo Activity";
    uid = "forgejo-activity";
    schemaVersion = 39;
    refresh = "1m";
    time = {
      from = "now-24h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "forgejo"
      "git"
    ];
    panels = [
      (panel {
        id = 1;
        title = "Forgejo log volume";
        x = 0;
        y = 0;
        w = 12;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, count() as value FROM otel.otel_logs WHERE Body LIKE '%forgejo%' AND ${tfLog} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 2;
        title = "Git operations (push/fetch)";
        x = 12;
        y = 0;
        w = 12;
        unit = "short";
        sql = "SELECT toStartOfHour(Timestamp) as time, count() as value FROM otel.otel_logs WHERE (Body LIKE '%git-receive-pack%' OR Body LIKE '%git-upload-pack%') AND ${tfLog} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 3;
        title = "Forgejo errors";
        x = 0;
        y = 8;
        w = 24;
        h = 10;
        type = "table";
        format = 2;
        sql = "SELECT Timestamp, substring(Body, 1, 200) as message FROM otel.otel_logs WHERE Body LIKE '%forgejo%' AND SeverityNumber >= 17 AND ${tfLog} ORDER BY Timestamp DESC LIMIT 50";
      })
      (panel {
        id = 4;
        title = "Recent git activity";
        x = 0;
        y = 18;
        w = 24;
        h = 10;
        type = "table";
        format = 2;
        sql = "SELECT Timestamp, substring(Body, 1, 200) as activity FROM otel.otel_logs WHERE (Body LIKE '%git-receive-pack%' OR Body LIKE '%git-upload-pack%' OR Body LIKE '%refs/heads%') AND ${tfLog} ORDER BY Timestamp DESC LIMIT 50";
      })
    ];
  };
}
