# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hypermodern // grafana // dashboards
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# "the sky above the port was the color of television, tuned to a dead channel."
#
# production-grade observability. every systemd service that matters gets graphs.
# counters use runningDifference() for proper rate derivation from OTel sums.
# layout: 24-column grid, collapsible row sections, stat panels at top for
# glanceability, time series for trends, tables for drill-down.
let
  # ── datasource ────────────────────────────────────────────────────────────────
  ds = {
    type = "grafana-clickhouse-datasource";
    uid = "clickhouse";
  };

  # ── time filter macros ────────────────────────────────────────────────────────
  tf = "$__timeFilter(TimeUnix)";
  tfLog = "$__timeFilter(Timestamp)";
  host = "ResourceAttributes['host.name']";

  # ── journald log helpers ──────────────────────────────────────────────────────
  # journald logs arrive as JSON in Body (MESSAGE, PRIORITY, _SYSTEMD_UNIT, etc.)
  # LogAttributes is empty; SeverityText/SeverityNumber are not populated.
  # syslog PRIORITY: 0=emerg, 1=alert, 2=crit, 3=err, 4=warn, 5=notice, 6=info, 7=debug
  unit = "JSONExtractString(Body, '_SYSTEMD_UNIT')";
  msg = "JSONExtractString(Body, 'MESSAGE')";
  pri = "JSONExtractInt(Body, 'PRIORITY')";
  isErr = "JSONExtractInt(Body, 'PRIORITY') <= 3"; # err + crit + alert + emerg
  isWarn = "JSONExtractInt(Body, 'PRIORITY') <= 4"; # includes warning

  # ── panel constructors ────────────────────────────────────────────────────────

  # base panel (time series)
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
      # optional overrides
      description ? "",
      thresholds ? null,
      fieldConfig ? { },
      options ? { },
      targets ? null,
      transformations ? [ ],
    }:
    let
      baseFieldConfig = {
        defaults = {
          inherit unit;
          custom = {
            lineWidth = 1;
            fillOpacity = 10;
            spanNulls = true;
            showPoints = "never";
          };
        }
        // (
          if thresholds != null then
            {
              inherit thresholds;
              color.mode = "thresholds";
            }
          else
            {
              color.mode = "palette-classic";
            }
        );
      }
      // fieldConfig;
    in
    {
      inherit
        id
        title
        type
        description
        ;
      gridPos = {
        inherit
          x
          y
          w
          h
          ;
      };
      datasource = ds;
      fieldConfig = baseFieldConfig;
      options = {
        tooltip.mode = "multi";
        tooltip.sort = "desc";
        legend = {
          displayMode = "table";
          placement = "bottom";
          calcs = [
            "mean"
            "max"
            "last"
          ];
        };
      }
      // options;
      targets =
        if targets != null then
          targets
        else
          [
            {
              rawSql = sql;
              inherit format;
              queryType = "sql";
              refId = "A";
            }
          ];
    }
    // (if transformations != [ ] then { inherit transformations; } else { });

  # stat panel (big number + sparkline)
  stat =
    {
      id,
      title,
      x ? 0,
      y ? 0,
      w ? 4,
      h ? 4,
      unit ? "short",
      sql,
      thresholds ? null,
      colorMode ? "background",
      format ? 2,
      description ? "",
    }:
    {
      inherit id title description;
      type = "stat";
      gridPos = {
        inherit
          x
          y
          w
          h
          ;
      };
      datasource = ds;
      fieldConfig.defaults = {
        inherit unit;
        color.mode = if thresholds != null then "thresholds" else "palette-classic";
      }
      // (if thresholds != null then { inherit thresholds; } else { });
      options = {
        graphMode = "area";
        textMode = "value";
        inherit colorMode;
        reduceOptions = {
          calcs = [ "lastNotNull" ];
          fields = "";
          values = false;
        };
      };
      targets = [
        {
          rawSql = sql;
          inherit format;
          queryType = "sql";
          refId = "A";
        }
      ];
    };

  # table panel
  table =
    {
      id,
      title,
      x ? 0,
      y ? 0,
      w ? 24,
      h ? 8,
      sql,
      description ? "",
      overrides ? [ ],
    }:
    {
      inherit id title description;
      type = "table";
      gridPos = {
        inherit
          x
          y
          w
          h
          ;
      };
      datasource = ds;
      fieldConfig.defaults = { };
      fieldConfig.overrides = overrides;
      options = {
        showHeader = true;
        sortBy = [ ];
      };
      targets = [
        {
          rawSql = sql;
          format = 2;
          queryType = "sql";
          refId = "A";
        }
      ];
    };

  # row (collapsible section divider)
  row =
    {
      id,
      title,
      y ? 0,
      collapsed ? false,
      panels ? [ ],
    }:
    {
      inherit id title;
      type = "row";
      gridPos = {
        x = 0;
        inherit y;
        w = 24;
        h = 1;
      };
      inherit collapsed panels;
    };

  # gauge panel
  gauge =
    {
      id,
      title,
      x ? 0,
      y ? 0,
      w ? 6,
      h ? 6,
      unit ? "percentunit",
      sql,
      min ? 0,
      max ? 1,
      thresholds ? null,
      description ? "",
    }:
    {
      inherit id title description;
      type = "gauge";
      gridPos = {
        inherit
          x
          y
          w
          h
          ;
      };
      datasource = ds;
      fieldConfig.defaults = {
        inherit unit min max;
        color.mode = if thresholds != null then "thresholds" else "palette-classic";
      }
      // (if thresholds != null then { inherit thresholds; } else { });
      options = {
        reduceOptions = {
          calcs = [ "lastNotNull" ];
          fields = "";
          values = false;
        };
        showThresholdLabels = false;
        showThresholdMarkers = true;
      };
      targets = [
        {
          rawSql = sql;
          format = 2;
          queryType = "sql";
          refId = "A";
        }
      ];
    };

  # ── common thresholds ─────────────────────────────────────────────────────────
  thresholdPct = {
    mode = "percentage";
    steps = [
      {
        color = "green";
        value = null;
      }
      {
        color = "yellow";
        value = 70;
      }
      {
        color = "red";
        value = 90;
      }
    ];
  };

  thresholdLoad = {
    mode = "absolute";
    steps = [
      {
        color = "green";
        value = null;
      }
      {
        color = "yellow";
        value = 4;
      }
      {
        color = "red";
        value = 8;
      }
    ];
  };

  thresholdErrors = {
    mode = "absolute";
    steps = [
      {
        color = "green";
        value = null;
      }
      {
        color = "yellow";
        value = 1;
      }
      {
        color = "red";
        value = 10;
      }
    ];
  };

  thresholdHealth = {
    mode = "absolute";
    steps = [
      {
        color = "red";
        value = null;
      }
      {
        color = "green";
        value = 1;
      }
    ];
  };

  # ── rate helper (ClickHouse runningDifference for OTel cumulative counters) ──
  # OTel sums are cumulative — we need per-interval deltas
  rate = metric: "runningDifference(Value)";

  # ── host filter clause ────────────────────────────────────────────────────────
  hostFilter = "(\${host:raw} = '' OR ${host} = '\${host:raw}')";
  hostFilterSingle = "${host} = '\$host'";

  # ── unit filter for log queries ───────────────────────────────────────────────
  unitIs = svc: "${unit} = '${svc}'";
  unitLike = pat: "${unit} LIKE '${pat}'";

  # ── standard template variables ───────────────────────────────────────────────
  hostVarAll = {
    name = "host";
    label = "Host";
    type = "query";
    datasource = ds;
    query = "SELECT DISTINCT ${host} FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1";
    multi = false;
    includeAll = true;
    current = {
      text = "All";
      value = "\$__all";
    };
  };

  hostVarSingle = {
    name = "host";
    label = "Host";
    type = "query";
    datasource = ds;
    query = "SELECT DISTINCT ${host} FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1";
    multi = false;
    includeAll = false;
  };

in
{
  # ════════════════════════════════════════════════════════════════════════════════
  #  1. Fleet Overview
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # the battle station. one glance tells you if the fleet is healthy.
  # top row: stat panels for instant health. below: time series for trends.
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
    templating.list = [ hostVarAll ];
    panels = [

      # ── row: health at a glance ──────────────────────────────────────────────
      (row {
        id = 100;
        title = "Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Hosts reporting";
        x = 0;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdHealth;
        sql = "SELECT uniq(${host}) as value FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 2;
        title = "Fleet load avg";
        x = 4;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdLoad;
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'system.cpu.load_average.1m' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 3;
        title = "Fleet memory %";
        x = 8;
        y = 1;
        w = 4;
        h = 4;
        unit = "percentunit";
        thresholds = thresholdPct;
        sql = "SELECT sum(case when Attributes['state'] = 'used' then Value else 0 end) / sum(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.memory.usage' AND TimeUnix > now() - INTERVAL 2 MINUTE AND TimeUnix = (SELECT max(TimeUnix) FROM otel.otel_metrics_sum WHERE MetricName = 'system.memory.usage' AND TimeUnix > now() - INTERVAL 2 MINUTE)";
      })
      (stat {
        id = 4;
        title = "Errors (5m)";
        x = 12;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        colorMode = "background";
        sql = "SELECT count() as value FROM otel.otel_logs WHERE ${isErr} AND Timestamp > now() - INTERVAL 5 MINUTE";
      })
      (stat {
        id = 5;
        title = "OTel points/min";
        x = 16;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() / 5 as value FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 5 MINUTE";
      })
      (stat {
        id = 6;
        title = "DNS queries/s";
        x = 20;
        y = 1;
        w = 4;
        h = 4;
        unit = "reqps";
        sql = "SELECT avg(rate) as value FROM (SELECT ${host} as h, runningDifference(Value) / 30 as rate FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0";
      })

      # ── row: compute ─────────────────────────────────────────────────────────
      (row {
        id = 101;
        title = "Compute";
        y = 5;
      })

      (panel {
        id = 10;
        title = "Load average (1m) by host";
        x = 0;
        y = 6;
        w = 8;
        h = 7;
        unit = "short";
        thresholds = thresholdLoad;
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'system.cpu.load_average.1m' AND ${tf} AND ${hostFilter} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 11;
        title = "Memory used by host";
        x = 8;
        y = 6;
        w = 8;
        h = 7;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.memory.usage' AND Attributes['state'] = 'used' AND ${tf} AND ${hostFilter} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 12;
        title = "Paging operations/sec by host";
        x = 16;
        y = 6;
        w = 8;
        h = 7;
        unit = "ops";
        sql = "SELECT TimeUnix as time, ${host} as host, Attributes['direction'] as dir, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.paging.operations' AND ${tf} AND ${hostFilter} GROUP BY time, host, dir ORDER BY time";
        description = "page in/out operations. high values = memory pressure, swapping.";
      })

      # ── row: storage ─────────────────────────────────────────────────────────
      (row {
        id = 102;
        title = "Storage";
        y = 13;
      })

      (panel {
        id = 20;
        title = "Disk I/O (read+write) by host";
        x = 0;
        y = 14;
        w = 12;
        h = 7;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, Attributes['direction'] as dir, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.disk.io' AND ${tf} AND ${hostFilter} GROUP BY time, host, dir ORDER BY time";
      })
      (panel {
        id = 21;
        title = "Filesystem used % by host";
        x = 12;
        y = 14;
        w = 12;
        h = 7;
        unit = "percentunit";
        thresholds = thresholdPct;
        sql = "SELECT TimeUnix as time, ${host} as host, Attributes['mountpoint'] as mount, sumIf(Value, Attributes['state'] = 'used') / sum(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.filesystem.usage' AND Attributes['mountpoint'] NOT LIKE '/nix%' AND ${tf} AND ${hostFilter} GROUP BY time, host, mount HAVING sum(Value) > 0 ORDER BY time";
        description = "filesystem usage as percentage. excludes /nix/store mounts.";
      })

      # ── row: network ─────────────────────────────────────────────────────────
      (row {
        id = 103;
        title = "Network";
        y = 21;
      })

      (panel {
        id = 30;
        title = "Network throughput by host";
        x = 0;
        y = 22;
        w = 12;
        h = 7;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, Attributes['direction'] as dir, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND Attributes['device'] != 'lo' AND ${tf} AND ${hostFilter} GROUP BY time, host, dir ORDER BY time";
      })
      (panel {
        id = 31;
        title = "Network errors + drops";
        x = 12;
        y = 22;
        w = 12;
        h = 7;
        unit = "short";
        thresholds = thresholdErrors;
        sql = "SELECT TimeUnix as time, ${host} as host, MetricName, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName IN ('system.network.errors', 'system.network.dropped') AND ${tf} AND ${hostFilter} GROUP BY time, host, MetricName ORDER BY time";
      })

      # ── row: services ────────────────────────────────────────────────────────
      (row {
        id = 104;
        title = "Services";
        y = 29;
      })

      (panel {
        id = 40;
        title = "CoreDNS queries/sec";
        x = 0;
        y = 30;
        w = 8;
        h = 7;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, ${host} as host, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND ${tf} AND ${hostFilter} AND runningDifference(Value) >= 0 ORDER BY host, time";
      })
      (panel {
        id = 41;
        title = "DNS cache hit rate";
        x = 8;
        y = 30;
        w = 8;
        h = 7;
        unit = "percentunit";
        sql = "SELECT h.TimeUnix as time, h.${host} as host, sum(h.Value) / (sum(h.Value) + sum(m.Value)) as value FROM otel.otel_metrics_sum h INNER JOIN otel.otel_metrics_sum m ON h.TimeUnix = m.TimeUnix AND h.${host} = m.${host} WHERE h.MetricName = 'coredns_cache_hits_total' AND m.MetricName = 'coredns_cache_misses_total' AND h.${tf} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 42;
        title = "PostgREST requests (JWT cache)";
        x = 16;
        y = 30;
        w = 8;
        h = 7;
        unit = "ops";
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName IN ('pgrst_jwt_cache_hits_total', 'pgrst_jwt_cache_requests_total') AND ${tf} GROUP BY time, metric ORDER BY time";
      })

      # ── row: errors ──────────────────────────────────────────────────────────
      (row {
        id = 105;
        title = "Recent Errors";
        y = 37;
      })

      (table {
        id = 50;
        title = "Error log (last hour)";
        x = 0;
        y = 38;
        w = 24;
        h = 10;
        sql = "SELECT Timestamp, ${host} as host, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', 'info') as level, JSONExtractString(Body, '_SYSTEMD_UNIT') as unit, substring(${msg}, 1, 300) as message FROM otel.otel_logs WHERE ${isErr} AND ${tfLog} AND ${hostFilter} ORDER BY Timestamp DESC LIMIT 200";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  2. Host Drill-Down
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # deep dive into a single host. every scraper gets a panel.
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
    templating.list = [ hostVarSingle ];
    panels = [

      # ── row: CPU ─────────────────────────────────────────────────────────────
      (row {
        id = 100;
        title = "CPU";
        y = 0;
      })

      (panel {
        id = 1;
        title = "CPU time by state";
        x = 0;
        y = 1;
        w = 12;
        h = 8;
        unit = "s";
        sql = "SELECT TimeUnix as time, Attributes['state'] as state, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.cpu.time' AND ${hostFilterSingle} AND ${tf} GROUP BY time, state ORDER BY time";
        options = {
          tooltip.mode = "multi";
          tooltip.sort = "desc";
          legend = {
            displayMode = "table";
            placement = "bottom";
            calcs = [
              "mean"
              "max"
              "last"
            ];
          };
        };
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 2;
        title = "Load averages (1m / 5m / 15m)";
        x = 12;
        y = 1;
        w = 12;
        h = 8;
        unit = "short";
        thresholds = thresholdLoad;
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName LIKE 'system.cpu.load_average%' AND ${hostFilterSingle} AND ${tf} GROUP BY time, metric ORDER BY time";
      })

      # ── row: memory ──────────────────────────────────────────────────────────
      (row {
        id = 101;
        title = "Memory";
        y = 9;
      })

      (panel {
        id = 3;
        title = "Memory by state";
        x = 0;
        y = 10;
        w = 12;
        h = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, Attributes['state'] as state, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.memory.usage' AND ${hostFilterSingle} AND ${tf} GROUP BY time, state ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 4;
        title = "Paging (swap I/O)";
        x = 12;
        y = 10;
        w = 12;
        h = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, Attributes['direction'] as dir, Attributes['type'] as type, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.paging.operations' AND ${hostFilterSingle} AND ${tf} GROUP BY time, dir, type ORDER BY time";
      })

      # ── row: disk ────────────────────────────────────────────────────────────
      (row {
        id = 102;
        title = "Disk";
        y = 18;
      })

      (panel {
        id = 5;
        title = "Disk I/O by device";
        x = 0;
        y = 19;
        w = 12;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, Attributes['device'] as device, Attributes['direction'] as dir, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.disk.io' AND ${hostFilterSingle} AND ${tf} GROUP BY time, device, dir ORDER BY time";
      })
      (panel {
        id = 6;
        title = "Filesystem usage by mount";
        x = 12;
        y = 19;
        w = 12;
        h = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, Attributes['mountpoint'] as mount, Attributes['state'] as state, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.filesystem.usage' AND ${hostFilterSingle} AND Attributes['mountpoint'] NOT LIKE '/nix%' AND ${tf} GROUP BY time, mount, state ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })

      # ── row: network ─────────────────────────────────────────────────────────
      (row {
        id = 103;
        title = "Network";
        y = 27;
      })

      (panel {
        id = 7;
        title = "Network I/O by interface";
        x = 0;
        y = 28;
        w = 12;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, Attributes['device'] as iface, Attributes['direction'] as dir, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND ${hostFilterSingle} AND Attributes['device'] != 'lo' AND ${tf} GROUP BY time, iface, dir ORDER BY time";
      })
      (panel {
        id = 8;
        title = "Network errors + drops";
        x = 12;
        y = 28;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT TimeUnix as time, MetricName as metric, Attributes['device'] as iface, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName IN ('system.network.errors', 'system.network.dropped') AND ${hostFilterSingle} AND ${tf} GROUP BY time, metric, iface ORDER BY time";
      })

      # ── row: logs ────────────────────────────────────────────────────────────
      (row {
        id = 104;
        title = "Logs";
        y = 36;
      })

      (panel {
        id = 9;
        title = "Log rate by severity";
        x = 0;
        y = 37;
        w = 24;
        h = 5;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE ${host} = '\$host' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (table {
        id = 10;
        title = "Recent logs";
        x = 0;
        y = 42;
        w = 24;
        h = 12;
        sql = "SELECT Timestamp, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', 'info') as level, JSONExtractString(Body, '_SYSTEMD_UNIT') as unit, substring(${msg}, 1, 300) as message FROM otel.otel_logs WHERE ${host} = '\$host' AND ${tfLog} ORDER BY Timestamp DESC LIMIT 500";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  3. ClickHouse Internals
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # the OLAP engine that stores our telemetry. watch it watch itself.
  # server on watchtower (:9363), keeper ensemble on ultraviolence/guccimane/shimmer (:9364).
  # metrics: ClickHouseMetrics_ (gauges), ClickHouseProfileEvents_ (counters),
  #          ClickHouseAsyncMetrics_ (computed gauges).
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

      # ── row: server health at a glance ───────────────────────────────────────
      (row {
        id = 100;
        title = "Server Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Active queries";
        x = 0;
        y = 1;
        w = 3;
        h = 4;
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_Query' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 2;
        title = "Uptime";
        x = 3;
        y = 1;
        w = 3;
        h = 4;
        unit = "s";
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_Uptime' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 3;
        title = "MergeTree size";
        x = 6;
        y = 1;
        w = 3;
        h = 4;
        unit = "bytes";
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_TotalBytesOfMergeTreeTables' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 4;
        title = "Total rows";
        x = 9;
        y = 1;
        w = 3;
        h = 4;
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_TotalRowsOfMergeTreeTables' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 5;
        title = "Active parts";
        x = 12;
        y = 1;
        w = 3;
        h = 4;
        thresholds = {
          mode = "absolute";
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "yellow";
              value = 200;
            }
            {
              color = "red";
              value = 500;
            }
          ];
        };
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_PartsActive' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 6;
        title = "Max parts/partition";
        x = 15;
        y = 1;
        w = 3;
        h = 4;
        thresholds = {
          mode = "absolute";
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "yellow";
              value = 100;
            }
            {
              color = "red";
              value = 300;
            }
          ];
        };
        description = ">300 triggers InsertDelay. Critical threshold for write availability.";
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_MaxPartCountForPartition' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 7;
        title = "Memory tracked";
        x = 18;
        y = 1;
        w = 3;
        h = 4;
        unit = "bytes";
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_MemoryTracking' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 8;
        title = "Delayed inserts";
        x = 21;
        y = 1;
        w = 3;
        h = 4;
        thresholds = thresholdErrors;
        description = "non-zero = back-pressure from parts overflow";
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_DelayedInserts' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })

      # ── row: query throughput ────────────────────────────────────────────────
      (row {
        id = 101;
        title = "Query Throughput";
        y = 5;
      })

      (panel {
        id = 10;
        title = "Queries running (concurrent)";
        x = 0;
        y = 6;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_Query' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 11;
        title = "SELECT queries/sec";
        x = 8;
        y = 6;
        w = 8;
        h = 8;
        unit = "qps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_SelectQuery' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 12;
        title = "INSERT queries/sec";
        x = 16;
        y = 6;
        w = 8;
        h = 8;
        unit = "qps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_InsertQuery' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })

      # ── row: insert throughput ───────────────────────────────────────────────
      (row {
        id = 102;
        title = "Insert Throughput";
        y = 14;
      })

      (panel {
        id = 13;
        title = "Inserted rows/sec";
        x = 0;
        y = 15;
        w = 8;
        h = 8;
        unit = "rows/s";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_InsertedRows' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 14;
        title = "Inserted bytes/sec";
        x = 8;
        y = 15;
        w = 8;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_InsertedBytes' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 15;
        title = "Failed queries (select + insert)";
        x = 16;
        y = 15;
        w = 8;
        h = 8;
        unit = "short";
        thresholds = thresholdErrors;
        sql = "SELECT TimeUnix as time, MetricName as metric, runningDifference(Value) as value FROM otel.otel_metrics_sum WHERE MetricName IN ('ClickHouseProfileEvents_FailedSelectQuery', 'ClickHouseProfileEvents_FailedInsertQuery') AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })

      # ── row: memory & jemalloc ───────────────────────────────────────────────
      (row {
        id = 103;
        title = "Memory";
        y = 23;
      })

      (panel {
        id = 20;
        title = "Memory tracked (server allocator)";
        x = 0;
        y = 24;
        w = 8;
        h = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_MemoryTracking' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 21;
        title = "jemalloc resident vs allocated";
        x = 8;
        y = 24;
        w = 8;
        h = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('ClickHouseAsyncMetrics_jemalloc_resident', 'ClickHouseAsyncMetrics_jemalloc_allocated') AND ${tf} GROUP BY time, metric ORDER BY time";
        description = "gap between resident and allocated = fragmentation";
      })
      (panel {
        id = 22;
        title = "OS memory free (without cached)";
        x = 16;
        y = 24;
        w = 8;
        h = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_OSMemoryFreeWithoutCached' AND ${tf} GROUP BY time ORDER BY time";
      })

      # ── row: merges & mutations ──────────────────────────────────────────────
      (row {
        id = 104;
        title = "Merges & Mutations";
        y = 32;
      })

      (panel {
        id = 30;
        title = "Background merges (concurrent)";
        x = 0;
        y = 33;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_Merge' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 31;
        title = "Merged rows/sec";
        x = 8;
        y = 33;
        w = 8;
        h = 8;
        unit = "rows/s";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_MergedRows' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 32;
        title = "Merge time (ms/interval)";
        x = 16;
        y = 33;
        w = 8;
        h = 8;
        unit = "ms";
        sql = "SELECT TimeUnix as time, runningDifference(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_MergeTotalMilliseconds' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })

      (panel {
        id = 33;
        title = "Parts: active vs outdated";
        x = 0;
        y = 41;
        w = 12;
        h = 8;
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('ClickHouseMetrics_PartsActive', 'ClickHouseMetrics_PartsOutdated') AND ${tf} GROUP BY time, metric ORDER BY time";
      })
      (panel {
        id = 34;
        title = "Max parts per partition";
        x = 12;
        y = 41;
        w = 12;
        h = 8;
        description = ">300 triggers InsertDelay, >600 = INSERT rejected. THE critical capacity metric.";
        thresholds = {
          mode = "absolute";
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "yellow";
              value = 100;
            }
            {
              color = "red";
              value = 300;
            }
          ];
        };
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_MaxPartCountForPartition' AND ${tf} GROUP BY time ORDER BY time";
      })

      # ── row: storage (MergeTree) ─────────────────────────────────────────────
      (row {
        id = 105;
        title = "Storage (MergeTree)";
        y = 49;
      })

      (panel {
        id = 40;
        title = "Total compressed size";
        x = 0;
        y = 50;
        w = 8;
        h = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_TotalBytesOfMergeTreeTables' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 41;
        title = "Total rows stored";
        x = 8;
        y = 50;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_TotalRowsOfMergeTreeTables' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 42;
        title = "Tables / databases";
        x = 16;
        y = 50;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('ClickHouseAsyncMetrics_NumberOfTables', 'ClickHouseAsyncMetrics_NumberOfDatabases') AND ${tf} GROUP BY time, metric ORDER BY time";
      })

      # ── row: S3 / R2 I/O ────────────────────────────────────────────────────
      (row {
        id = 106;
        title = "S3 / R2 (Object Storage)";
        y = 58;
      })

      (panel {
        id = 50;
        title = "S3 read bytes/sec";
        x = 0;
        y = 59;
        w = 6;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_ReadBufferFromS3Bytes' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 51;
        title = "S3 write bytes/sec";
        x = 6;
        y = 59;
        w = 6;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_WriteBufferFromS3Bytes' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 52;
        title = "S3 read requests/sec";
        x = 12;
        y = 59;
        w = 6;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_S3ReadRequestsCount' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 53;
        title = "S3 write requests/sec";
        x = 18;
        y = 59;
        w = 6;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_S3WriteRequestsCount' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })

      # ── row: disk I/O ────────────────────────────────────────────────────────
      (row {
        id = 107;
        title = "Disk I/O";
        y = 67;
      })

      (panel {
        id = 54;
        title = "Disk read time (ms/interval)";
        x = 0;
        y = 68;
        w = 8;
        h = 8;
        unit = "ms";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_DiskReadElapsedMicroseconds' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 55;
        title = "Disk write time (ms/interval)";
        x = 8;
        y = 68;
        w = 8;
        h = 8;
        unit = "ms";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_DiskWriteElapsedMicroseconds' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 56;
        title = "Open file descriptors (R/W)";
        x = 16;
        y = 68;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('ClickHouseMetrics_OpenFileForRead', 'ClickHouseMetrics_OpenFileForWrite') AND ${tf} GROUP BY time, metric ORDER BY time";
      })

      # ── row: connections & network ───────────────────────────────────────────
      (row {
        id = 108;
        title = "Connections & Network";
        y = 76;
      })

      (panel {
        id = 60;
        title = "Connections by type";
        x = 0;
        y = 77;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('ClickHouseMetrics_TCPConnection', 'ClickHouseMetrics_HTTPConnection', 'ClickHouseMetrics_InterserverConnection') AND ${tf} GROUP BY time, metric ORDER BY time";
      })
      (panel {
        id = 61;
        title = "Network send bytes/sec";
        x = 8;
        y = 77;
        w = 8;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_NetworkSendBytes' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 62;
        title = "Network receive bytes/sec";
        x = 16;
        y = 77;
        w = 8;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_NetworkReceiveBytes' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })

      # ── row: replication ─────────────────────────────────────────────────────
      (row {
        id = 109;
        title = "Replication";
        y = 85;
      })

      (panel {
        id = 70;
        title = "Replica fetch / send (concurrent)";
        x = 0;
        y = 86;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('ClickHouseMetrics_ReplicatedFetch', 'ClickHouseMetrics_ReplicatedSend') AND ${tf} GROUP BY time, metric ORDER BY time";
      })
      (panel {
        id = 71;
        title = "Max replication queue size";
        x = 8;
        y = 86;
        w = 8;
        h = 8;
        description = "max queue across all replicated tables. >0 = replica is behind.";
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_ReplicasMaxQueueSize' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 72;
        title = "Max replica delay (seconds)";
        x = 16;
        y = 86;
        w = 8;
        h = 8;
        unit = "s";
        thresholds = {
          mode = "absolute";
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "yellow";
              value = 30;
            }
            {
              color = "red";
              value = 300;
            }
          ];
        };
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseAsyncMetrics_ReplicasMaxAbsoluteDelay' AND ${tf} GROUP BY time ORDER BY time";
      })

      # ── row: threads & background pools ──────────────────────────────────────
      (row {
        id = 110;
        title = "Threads & Pools";
        y = 94;
      })

      (panel {
        id = 80;
        title = "Global threads (total / active)";
        x = 0;
        y = 95;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('ClickHouseMetrics_GlobalThread', 'ClickHouseMetrics_GlobalThreadActive') AND ${tf} GROUP BY time, metric ORDER BY time";
      })
      (panel {
        id = 81;
        title = "Background pool tasks";
        x = 8;
        y = 95;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('ClickHouseMetrics_BackgroundMergesAndMutationsPoolTask', 'ClickHouseMetrics_BackgroundSchedulePoolTask') AND ${tf} GROUP BY time, metric ORDER BY time";
      })
      (panel {
        id = 82;
        title = "CPU time (ms/interval)";
        x = 16;
        y = 95;
        w = 8;
        h = 8;
        unit = "ms";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_OSCPUVirtualTimeMicroseconds' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
        description = "server process CPU (user+system). divide by interval for utilization.";
      })

      # ── row: ZooKeeper client (server → keeper) ──────────────────────────────
      (row {
        id = 111;
        title = "ZooKeeper Client (Server → Keeper)";
        y = 103;
      })

      (panel {
        id = 90;
        title = "ZK in-flight requests";
        x = 0;
        y = 104;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_ZooKeeperRequest' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 91;
        title = "ZK watches";
        x = 8;
        y = 104;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_ZooKeeperWatch' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 92;
        title = "ZK operations/sec (get/set/create/txn)";
        x = 16;
        y = 104;
        w = 8;
        h = 8;
        unit = "ops";
        sql = "SELECT TimeUnix as time, MetricName as metric, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName IN ('ClickHouseProfileEvents_ZooKeeperGet', 'ClickHouseProfileEvents_ZooKeeperSet', 'ClickHouseProfileEvents_ZooKeeperCreate', 'ClickHouseProfileEvents_ZooKeeperTransactions') AND ${tf} AND runningDifference(Value) >= 0 ORDER BY MetricName, time";
      })

      # ── row: Keeper ensemble (3-node metrics from :9364) ─────────────────────
      (row {
        id = 112;
        title = "Keeper Ensemble (3 nodes)";
        y = 112;
      })

      (panel {
        id = 93;
        title = "Keeper sessions by node";
        x = 0;
        y = 113;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, ${host} as keeper, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_ZooKeeperSession' AND ${host} IN ('ultraviolence', 'guccimane', 'shimmer') AND ${tf} GROUP BY time, keeper ORDER BY time";
        description = "active client sessions per keeper node";
      })
      (panel {
        id = 94;
        title = "Keeper requests by node";
        x = 8;
        y = 113;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, ${host} as keeper, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_ZooKeeperRequest' AND ${host} IN ('ultraviolence', 'guccimane', 'shimmer') AND ${tf} GROUP BY time, keeper ORDER BY time";
      })
      (panel {
        id = 95;
        title = "Keeper watches by node";
        x = 16;
        y = 113;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, ${host} as keeper, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'ClickHouseMetrics_ZooKeeperWatch' AND ${host} IN ('ultraviolence', 'guccimane', 'shimmer') AND ${tf} GROUP BY time, keeper ORDER BY time";
      })

      # ── row: compression & IO wait ──────────────────────────────────────────
      (row {
        id = 113;
        title = "Compression & IO Wait";
        y = 121;
      })

      (panel {
        id = 96;
        title = "Compressed read bytes/sec";
        x = 0;
        y = 122;
        w = 8;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_CompressedReadBufferBytes' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
      })
      (panel {
        id = 97;
        title = "S3 write latency (ms/interval)";
        x = 8;
        y = 122;
        w = 8;
        h = 8;
        unit = "ms";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_DiskS3WriteMicroseconds' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
        description = "time spent on S3/R2 write operations. spikes = storage latency.";
      })
      (panel {
        id = 98;
        title = "IO wait time (ms/interval)";
        x = 16;
        y = 122;
        w = 8;
        h = 8;
        unit = "ms";
        sql = "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM otel.otel_metrics_sum WHERE MetricName = 'ClickHouseProfileEvents_OSIOWaitMicroseconds' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
        description = "CPU idle time waiting for I/O. high values = storage bottleneck.";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  4. Log Explorer
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # structured log search. filter by host, unit, severity, full-text.
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
      hostVarAll
      {
        name = "unit";
        label = "Unit";
        type = "query";
        datasource = ds;
        query = "SELECT DISTINCT JSONExtractString(Body, '_SYSTEMD_UNIT') FROM otel.otel_logs WHERE Timestamp > now() - INTERVAL 1 HOUR AND JSONExtractString(Body, '_SYSTEMD_UNIT') != '' ORDER BY 1";
        multi = false;
        includeAll = true;
        current = {
          text = "All";
          value = "\$__all";
        };
      }
      {
        name = "severity";
        label = "Severity";
        type = "custom";
        query = "DEBUG,INFO,WARN,ERROR,FATAL";
        multi = true;
        includeAll = true;
        current = {
          text = "All";
          value = "\$__all";
        };
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

      # ── volume chart ─────────────────────────────────────────────────────────
      (panel {
        id = 1;
        title = "Log volume by severity";
        x = 0;
        y = 0;
        w = 24;
        h = 6;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE ${tfLog} AND ${hostFilter} AND (\${unit:raw} = '' OR JSONExtractString(Body, '_SYSTEMD_UNIT') = '\${unit:raw}') GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })

      # ── error breakdown ──────────────────────────────────────────────────────
      (panel {
        id = 2;
        title = "Error count by host";
        x = 0;
        y = 6;
        w = 8;
        h = 7;
        type = "bargauge";
        unit = "short";
        sql = "SELECT ${host} as host, count() as errors FROM otel.otel_logs WHERE ${isErr} AND ${tfLog} GROUP BY host ORDER BY errors DESC";
        format = 2;
      })
      (panel {
        id = 3;
        title = "Error count by unit";
        x = 8;
        y = 6;
        w = 8;
        h = 7;
        type = "bargauge";
        unit = "short";
        sql = "SELECT JSONExtractString(Body, '_SYSTEMD_UNIT') as unit, count() as errors FROM otel.otel_logs WHERE ${isErr} AND JSONExtractString(Body, '_SYSTEMD_UNIT') != '' AND ${tfLog} GROUP BY unit ORDER BY errors DESC LIMIT 15";
        format = 2;
      })
      (table {
        id = 4;
        title = "Top error messages";
        x = 16;
        y = 6;
        w = 8;
        h = 7;
        sql = "SELECT substring(${msg}, 1, 120) as message, count() as n FROM otel.otel_logs WHERE ${isErr} AND ${tfLog} GROUP BY message ORDER BY n DESC LIMIT 20";
      })

      # ── full stream ──────────────────────────────────────────────────────────
      (table {
        id = 5;
        title = "Log stream";
        x = 0;
        y = 13;
        w = 24;
        h = 14;
        sql = "SELECT Timestamp, ${host} as host, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', 'info') as level, JSONExtractString(Body, '_SYSTEMD_UNIT') as unit, substring(${msg}, 1, 400) as message FROM otel.otel_logs WHERE ${tfLog} AND ${hostFilter} AND (\${unit:raw} = '' OR JSONExtractString(Body, '_SYSTEMD_UNIT') = '\${unit:raw}') AND (\${search} = '' OR Body LIKE '%\${search}%') ORDER BY Timestamp DESC LIMIT 500";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  5. Service Health Matrix
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # which services are up, which are erroring, and how recently they reported.
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

      (row {
        id = 100;
        title = "Fleet Status";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Hosts UP";
        x = 0;
        y = 1;
        w = 6;
        h = 5;
        thresholds = thresholdHealth;
        sql = "SELECT uniq(${host}) as value FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 2;
        title = "Errors (5m)";
        x = 6;
        y = 1;
        w = 6;
        h = 5;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE ${isErr} AND Timestamp > now() - INTERVAL 5 MINUTE";
      })
      (stat {
        id = 3;
        title = "Data points/min";
        x = 12;
        y = 1;
        w = 6;
        h = 5;
        sql = "SELECT count() / 5 as value FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 5 MINUTE";
      })
      (stat {
        id = 4;
        title = "Log lines/min";
        x = 18;
        y = 1;
        w = 6;
        h = 5;
        sql = "SELECT count() / 5 as value FROM otel.otel_logs WHERE Timestamp > now() - INTERVAL 5 MINUTE";
      })

      (row {
        id = 101;
        title = "Host Liveness";
        y = 6;
      })

      (table {
        id = 10;
        title = "Host last-seen";
        x = 0;
        y = 7;
        w = 24;
        h = 7;
        sql = "SELECT ${host} as host, max(TimeUnix) as last_seen, dateDiff('second', max(TimeUnix), now()) as seconds_ago, if(dateDiff('second', max(TimeUnix), now()) < 120, 'UP', 'DOWN') as status FROM otel.otel_metrics_gauge WHERE TimeUnix > now() - INTERVAL 10 MINUTE GROUP BY host ORDER BY seconds_ago ASC";
      })

      (row {
        id = 102;
        title = "Service Errors (by systemd unit)";
        y = 14;
      })

      (table {
        id = 20;
        title = "Top erroring units (last hour)";
        x = 0;
        y = 15;
        w = 24;
        h = 9;
        sql = "SELECT ${host} as host, JSONExtractString(Body, '_SYSTEMD_UNIT') as unit, count() as errors, max(Timestamp) as last_error FROM otel.otel_logs WHERE ${isErr} AND Timestamp > now() - INTERVAL 1 HOUR AND JSONExtractString(Body, '_SYSTEMD_UNIT') != '' GROUP BY host, unit ORDER BY errors DESC LIMIT 30";
      })

      (row {
        id = 103;
        title = "OTel Pipeline Health";
        y = 24;
      })

      (panel {
        id = 30;
        title = "Metric ingestion rate";
        x = 0;
        y = 25;
        w = 12;
        h = 7;
        unit = "short";
        sql = "SELECT toStartOfMinute(TimeUnix) as time, count() as value FROM otel.otel_metrics_gauge WHERE ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 31;
        title = "Log ingestion rate";
        x = 12;
        y = 25;
        w = 12;
        h = 7;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, count() as value FROM otel.otel_logs WHERE ${tfLog} GROUP BY time ORDER BY time";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  6. Network Topology
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # fleet network health: throughput, errors, drops, connections per host.
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
    templating.list = [ hostVarAll ];
    panels = [

      (row {
        id = 100;
        title = "Throughput";
        y = 0;
      })

      (panel {
        id = 1;
        title = "TX by host (excl. loopback)";
        x = 0;
        y = 1;
        w = 12;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND Attributes['direction'] = 'transmit' AND Attributes['device'] != 'lo' AND ${tf} AND ${hostFilter} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 2;
        title = "RX by host (excl. loopback)";
        x = 12;
        y = 1;
        w = 12;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND Attributes['direction'] = 'receive' AND Attributes['device'] != 'lo' AND ${tf} AND ${hostFilter} GROUP BY time, host ORDER BY time";
      })

      (row {
        id = 101;
        title = "Errors & Drops";
        y = 9;
      })

      (panel {
        id = 3;
        title = "Network errors by host";
        x = 0;
        y = 10;
        w = 12;
        h = 8;
        unit = "short";
        thresholds = thresholdErrors;
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.errors' AND ${tf} AND ${hostFilter} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 4;
        title = "Dropped packets by host";
        x = 12;
        y = 10;
        w = 12;
        h = 8;
        unit = "short";
        thresholds = thresholdErrors;
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.dropped' AND ${tf} AND ${hostFilter} GROUP BY time, host ORDER BY time";
      })

      (row {
        id = 102;
        title = "Connections";
        y = 18;
      })

      (panel {
        id = 5;
        title = "Active TCP connections by host";
        x = 0;
        y = 19;
        w = 24;
        h = 8;
        unit = "short";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.connections' AND Attributes['protocol'] = 'tcp' AND ${tf} AND ${hostFilter} GROUP BY time, host ORDER BY time";
      })

      (row {
        id = 103;
        title = "Tailscale Interface";
        y = 27;
      })

      (panel {
        id = 6;
        title = "Tailscale TX";
        x = 0;
        y = 28;
        w = 12;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND Attributes['device'] = 'tailscale0' AND Attributes['direction'] = 'transmit' AND ${tf} AND ${hostFilter} GROUP BY time, host ORDER BY time";
      })
      (panel {
        id = 7;
        title = "Tailscale RX";
        x = 12;
        y = 28;
        w = 12;
        h = 8;
        unit = "Bps";
        sql = "SELECT TimeUnix as time, ${host} as host, avg(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'system.network.io' AND Attributes['device'] = 'tailscale0' AND Attributes['direction'] = 'receive' AND ${tf} AND ${hostFilter} GROUP BY time, host ORDER BY time";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  7. CoreDNS
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # split-horizon fleet DNS. 5 nodes run CoreDNS (all except shannon).
  # 4 server blocks: authoritative zone (sju1.s4.gl), CNAME template (s4.gl),
  # tailnet forward (MagicDNS), catch-all forward (1.1.1.1/8.8.8.8).
  # metrics from the prometheus plugin on :9153, scraped by local OTel agent.
  coredns = {
    title = "CoreDNS";
    uid = "coredns";
    schemaVersion = 39;
    refresh = "30s";
    time = {
      from = "now-1h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "dns"
      "coredns"
    ];
    templating.list = [ hostVarAll ];
    panels = [

      # ── row: health at a glance ──────────────────────────────────────────────
      (row {
        id = 100;
        title = "Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Queries/sec (fleet)";
        x = 0;
        y = 1;
        w = 4;
        h = 4;
        unit = "reqps";
        sql = "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) / 30 as rate FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0";
      })
      (stat {
        id = 2;
        title = "Cache entries";
        x = 4;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT sum(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'coredns_cache_entries' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 3;
        title = "SERVFAIL/sec";
        x = 8;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) / 30 as rate FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_responses_total' AND Attributes['rcode'] = 'SERVFAIL' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0";
      })
      (stat {
        id = 4;
        title = "Panics";
        x = 12;
        y = 1;
        w = 4;
        h = 4;
        thresholds = {
          mode = "absolute";
          steps = [
            {
              color = "green";
              value = null;
            }
            {
              color = "red";
              value = 1;
            }
          ];
        };
        sql = "SELECT sum(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_panics_total' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 5;
        title = "Nodes serving DNS";
        x = 16;
        y = 1;
        w = 4;
        h = 4;
        thresholds = {
          mode = "absolute";
          steps = [
            {
              color = "red";
              value = null;
            }
            {
              color = "yellow";
              value = 3;
            }
            {
              color = "green";
              value = 5;
            }
          ];
        };
        sql = "SELECT uniq(${host}) as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 6;
        title = "Healthcheck failures";
        x = 20;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) as rate FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_forward_healthcheck_broken_total' AND TimeUnix > now() - INTERVAL 5 MINUTE ORDER BY TimeUnix) WHERE rate >= 0";
      })

      # ── row: query rate ──────────────────────────────────────────────────────
      (row {
        id = 101;
        title = "Query Rate";
        y = 5;
      })

      (panel {
        id = 10;
        title = "Queries/sec by node";
        x = 0;
        y = 6;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, ${host} as node, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND ${tf} AND ${hostFilter} AND runningDifference(Value) >= 0 ORDER BY node, time";
      })
      (panel {
        id = 11;
        title = "Queries/sec by type (A, AAAA, PTR, SRV, ...)";
        x = 12;
        y = 6;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, Attributes['type'] as qtype, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, qtype ORDER BY time";
      })

      # ── row: responses & rcodes ──────────────────────────────────────────────
      (row {
        id = 102;
        title = "Responses & RCODEs";
        y = 14;
      })

      (panel {
        id = 20;
        title = "Responses/sec by RCODE";
        x = 0;
        y = 15;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, Attributes['rcode'] as rcode, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_responses_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, rcode ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })
      (panel {
        id = 21;
        title = "NXDOMAIN + SERVFAIL rate";
        x = 12;
        y = 15;
        w = 12;
        h = 8;
        unit = "reqps";
        thresholds = thresholdErrors;
        sql = "SELECT TimeUnix as time, Attributes['rcode'] as rcode, ${host} as node, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_responses_total' AND Attributes['rcode'] IN ('NXDOMAIN', 'SERVFAIL') AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, rcode, node ORDER BY time";
        description = "non-zero SERVFAIL = upstream or config problem. NXDOMAIN is informational.";
      })

      # ── row: latency ─────────────────────────────────────────────────────────
      (row {
        id = 103;
        title = "Latency";
        y = 23;
      })

      (panel {
        id = 30;
        title = "Request duration (p50/p95/p99) — all zones";
        x = 0;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        description = "total requests/sec split by responding plugin (file, template, forward, cache)";
        sql = "SELECT TimeUnix as time, Attributes['plugin'] as plugin, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_responses_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, plugin ORDER BY time";
      })
      (panel {
        id = 31;
        title = "Proxy healthcheck failures by upstream";
        x = 12;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        thresholds = thresholdErrors;
        sql = "SELECT TimeUnix as time, Attributes['to'] as upstream, runningDifference(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_proxy_healthcheck_failures_total' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
        description = "per-upstream health failures. non-zero = upstream returning errors.";
      })

      # ── row: cache ───────────────────────────────────────────────────────────
      (row {
        id = 104;
        title = "Cache";
        y = 32;
      })

      (panel {
        id = 40;
        title = "Cache hit rate (success + denial)";
        x = 0;
        y = 33;
        w = 8;
        h = 8;
        unit = "percentunit";
        sql = "SELECT TimeUnix as time, sum(h.Value) / (sum(h.Value) + sum(m.Value)) as value FROM otel.otel_metrics_sum h INNER JOIN otel.otel_metrics_sum m ON h.TimeUnix = m.TimeUnix WHERE h.MetricName = 'coredns_cache_hits_total' AND m.MetricName = 'coredns_cache_misses_total' AND h.${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 41;
        title = "Cache hits/sec by type";
        x = 8;
        y = 33;
        w = 8;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, Attributes['type'] as cache_type, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_cache_hits_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, cache_type ORDER BY time";
        description = "type=success (positive cache), type=denial (NXDOMAIN/NODATA cache)";
      })
      (panel {
        id = 42;
        title = "Cache entries (current)";
        x = 16;
        y = 33;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, ${host} as node, Attributes['type'] as cache_type, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'coredns_cache_entries' AND ${tf} AND ${hostFilter} GROUP BY time, node, cache_type ORDER BY time";
      })

      (panel {
        id = 43;
        title = "Cache misses/sec by node";
        x = 0;
        y = 41;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, ${host} as node, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_cache_misses_total' AND ${tf} AND ${hostFilter} AND runningDifference(Value) >= 0 ORDER BY node, time";
      })
      (panel {
        id = 44;
        title = "Cache requests/sec (total lookups)";
        x = 12;
        y = 41;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, ${host} as node, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_cache_requests_total' AND ${tf} AND ${hostFilter} AND runningDifference(Value) >= 0 ORDER BY node, time";
        description = "total cache lookups per node (hits + misses)";
      })

      # ── row: forwarding ──────────────────────────────────────────────────────
      (row {
        id = 105;
        title = "Forwarding (Upstreams)";
        y = 49;
      })

      (panel {
        id = 50;
        title = "Proxy conn cache hits/sec by upstream";
        x = 0;
        y = 50;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, Attributes['to'] as upstream, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_proxy_conn_cache_hits_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, upstream ORDER BY time";
        description = "connection reuse to upstreams (1.1.1.1, 8.8.8.8, 100.100.100.100 MagicDNS)";
      })
      (panel {
        id = 51;
        title = "Proxy conn cache misses/sec by upstream";
        x = 12;
        y = 50;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, Attributes['to'] as upstream, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_proxy_conn_cache_misses_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, upstream ORDER BY time";
        description = "new connections opened to upstreams (high = churn)";
      })

      (panel {
        id = 52;
        title = "Upstream healthcheck failures";
        x = 0;
        y = 58;
        w = 12;
        h = 8;
        thresholds = thresholdErrors;
        sql = "SELECT TimeUnix as time, Attributes['to'] as upstream, runningDifference(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_forward_healthcheck_broken_total' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
        description = "all upstreams marked unhealthy — spraying randomly. critical.";
      })
      (panel {
        id = 53;
        title = "Connection cache hits vs misses";
        x = 12;
        y = 58;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, MetricName as metric, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName IN ('coredns_proxy_conn_cache_hits_total', 'coredns_proxy_conn_cache_misses_total') AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, metric ORDER BY time";
        description = "high miss rate = excessive connection churn to upstreams";
      })

      # ── row: zones ───────────────────────────────────────────────────────────
      (row {
        id = 106;
        title = "Zones & Templates";
        y = 66;
      })

      (panel {
        id = 60;
        title = "Queries by zone";
        x = 0;
        y = 67;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, Attributes['zone'] as zone, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, zone ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })
      (panel {
        id = 61;
        title = "Template matches (CNAME rewrites)";
        x = 12;
        y = 67;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, ${host} as node, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_template_matches_total' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY node, time";
        description = "short-alias rewrites (*.s4.gl -> *.sju1.s4.gl). healthy = non-zero.";
      })

      # ── row: request/response sizes ──────────────────────────────────────────
      (row {
        id = 107;
        title = "Wire Sizes";
        y = 75;
      })

      (panel {
        id = 70;
        title = "Cache requests vs hits/sec";
        x = 0;
        y = 76;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, MetricName as metric, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName IN ('coredns_cache_requests_total', 'coredns_cache_hits_total') AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, metric ORDER BY time";
      })
      (panel {
        id = 71;
        title = "Template match rate (CNAME rewrites/sec)";
        x = 12;
        y = 76;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, ${host} as node, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_template_matches_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, node ORDER BY time";
        description = "short-alias zone CNAME rewrites (*.s4.gl → *.sju1.s4.gl)";
      })

      # ── row: protocol ────────────────────────────────────────────────────────
      (row {
        id = 108;
        title = "Protocol Breakdown";
        y = 84;
      })

      (panel {
        id = 80;
        title = "Queries by protocol (UDP vs TCP)";
        x = 0;
        y = 85;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, Attributes['proto'] as proto, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, proto ORDER BY time";
      })
      (panel {
        id = 81;
        title = "Queries by family (IPv4 vs IPv6)";
        x = 12;
        y = 85;
        w = 12;
        h = 8;
        unit = "reqps";
        sql = "SELECT TimeUnix as time, Attributes['family'] as family, sum(runningDifference(Value)) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName = 'coredns_dns_requests_total' AND ${tf} AND runningDifference(Value) >= 0 GROUP BY time, family ORDER BY time";
        description = "family=1 (IPv4), family=2 (IPv6)";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  9. Supabase / PostgreSQL
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # the PG17 cluster backing forgejo, attic, and supabase services.
  # PostgREST metrics from :3001 — pool, JWT cache, schema cache.
  # GoTrue (JSON structured logs): auth events, login/signup/token.
  # Storage (JSON structured logs): upload/download, 4xx/5xx.
  # Realtime (Elixir logs): channel events, crashes.
  supabase-postgres = {
    title = "Supabase / PostgreSQL";
    uid = "supabase-postgres";
    schemaVersion = 39;
    refresh = "30s";
    time = {
      from = "now-1h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "supabase"
      "postgres"
    ];
    panels = [

      # ── row: health ──────────────────────────────────────────────────────────
      (row {
        id = 100;
        title = "Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Pool available";
        x = 0;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'pgrst_db_pool_available' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 2;
        title = "Pool waiting";
        x = 4;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'pgrst_db_pool_waiting' AND TimeUnix > now() - INTERVAL 2 MINUTE";
        description = "requests queued for a pool connection. non-zero = saturated.";
      })
      (stat {
        id = 3;
        title = "Pool timeouts";
        x = 8;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) as rate FROM otel.otel_metrics_sum WHERE MetricName = 'pgrst_db_pool_timeouts_total' AND TimeUnix > now() - INTERVAL 5 MINUTE ORDER BY TimeUnix) WHERE rate >= 0";
      })
      (stat {
        id = 4;
        title = "Schema cache query time";
        x = 12;
        y = 1;
        w = 4;
        h = 4;
        unit = "s";
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'pgrst_schema_cache_query_time_seconds' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 5;
        title = "PG17 errors (5m)";
        x = 16;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-db.service' AND ${isErr} AND Timestamp > now() - INTERVAL 5 MINUTE";
      })
      (stat {
        id = 6;
        title = "Auth errors (5m)";
        x = 20;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-auth.service' AND ${isErr} AND Timestamp > now() - INTERVAL 5 MINUTE";
      })

      # ── row: PostgREST connection pool ───────────────────────────────────────
      (row {
        id = 101;
        title = "PostgREST Connection Pool";
        y = 5;
      })

      (panel {
        id = 10;
        title = "Pool connections (available / max)";
        x = 0;
        y = 6;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('pgrst_db_pool_available', 'pgrst_db_pool_max') AND ${tf} GROUP BY time, metric ORDER BY time";
      })
      (panel {
        id = 11;
        title = "Pool waiting requests";
        x = 8;
        y = 6;
        w = 8;
        h = 8;
        thresholds = thresholdErrors;
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'pgrst_db_pool_waiting' AND ${tf} GROUP BY time ORDER BY time";
        description = "queued requests waiting for a free connection";
      })
      (panel {
        id = 12;
        title = "Pool timeouts/interval";
        x = 16;
        y = 6;
        w = 8;
        h = 8;
        thresholds = thresholdErrors;
        sql = "SELECT TimeUnix as time, runningDifference(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'pgrst_db_pool_timeouts_total' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
        description = "each timeout = a failed request. critical if non-zero.";
      })

      # ── row: PostgREST JWT & schema ──────────────────────────────────────────
      (row {
        id = 102;
        title = "PostgREST JWT & Schema Cache";
        y = 14;
      })

      (panel {
        id = 13;
        title = "JWT cache hit rate";
        x = 0;
        y = 15;
        w = 8;
        h = 8;
        unit = "percentunit";
        sql = "SELECT TimeUnix as time, if(sum(req.Value) > 0, sum(hit.Value) / sum(req.Value), 1) as value FROM otel.otel_metrics_sum hit INNER JOIN otel.otel_metrics_sum req ON hit.TimeUnix = req.TimeUnix WHERE hit.MetricName = 'pgrst_jwt_cache_hits_total' AND req.MetricName = 'pgrst_jwt_cache_requests_total' AND hit.${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 14;
        title = "JWT cache ops/sec (requests, hits, evictions)";
        x = 8;
        y = 15;
        w = 8;
        h = 8;
        unit = "ops";
        sql = "SELECT TimeUnix as time, MetricName as metric, runningDifference(Value) / 30 as value FROM otel.otel_metrics_sum WHERE MetricName IN ('pgrst_jwt_cache_requests_total', 'pgrst_jwt_cache_hits_total', 'pgrst_jwt_cache_evictions_total') AND ${tf} AND runningDifference(Value) >= 0 ORDER BY MetricName, time";
      })
      (panel {
        id = 15;
        title = "Schema cache loads (success/fail)";
        x = 16;
        y = 15;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, Attributes['status'] as status, runningDifference(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'pgrst_schema_cache_loads_total' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
        description = "status=FAIL = schema reload failed, PostgREST may serve stale schema";
      })

      # ── row: GoTrue / Auth ───────────────────────────────────────────────────
      (row {
        id = 103;
        title = "GoTrue / Auth";
        y = 23;
      })

      (panel {
        id = 20;
        title = "Auth log volume by severity";
        x = 0;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-auth.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 21;
        title = "Auth events (login/signup/token/oauth2)";
        x = 12;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, multiIf(Body LIKE '%login%' OR Body LIKE '%signin%', 'login', Body LIKE '%signup%' OR Body LIKE '%register%', 'signup', Body LIKE '%token%' OR Body LIKE '%refresh%', 'token', Body LIKE '%oauth%' OR Body LIKE '%oidc%', 'oauth', 'other') as event, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-auth.service' AND ${tfLog} AND (Body LIKE '%login%' OR Body LIKE '%signup%' OR Body LIKE '%token%' OR Body LIKE '%oauth%' OR Body LIKE '%signin%' OR Body LIKE '%register%' OR Body LIKE '%refresh%' OR Body LIKE '%oidc%') GROUP BY time, event ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })

      # ── row: Storage & Realtime ──────────────────────────────────────────────
      (row {
        id = 104;
        title = "Storage & Realtime";
        y = 32;
      })

      (panel {
        id = 30;
        title = "Storage API log volume";
        x = 0;
        y = 33;
        w = 8;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-storage.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 31;
        title = "Realtime log volume";
        x = 8;
        y = 33;
        w = 8;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-realtime.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 32;
        title = "Meta + Studio log volume";
        x = 16;
        y = 33;
        w = 8;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, JSONExtractString(Body, '_SYSTEMD_UNIT') as svc, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') IN ('supabase-meta.service', 'supabase-studio.service') AND ${tfLog} GROUP BY time, svc ORDER BY time";
      })

      # ── row: PostgreSQL logs ─────────────────────────────────────────────────
      (row {
        id = 105;
        title = "PostgreSQL 17";
        y = 41;
      })

      (panel {
        id = 40;
        title = "PG17 log volume by severity";
        x = 0;
        y = 42;
        w = 24;
        h = 6;
        unit = "short";
        sql = "SELECT toStartOfMinute(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-db.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })

      # ── row: errors ──────────────────────────────────────────────────────────
      (row {
        id = 106;
        title = "All Errors";
        y = 48;
      })

      (table {
        id = 50;
        title = "Supabase stack errors (all services)";
        x = 0;
        y = 49;
        w = 24;
        h = 10;
        sql = "SELECT Timestamp, JSONExtractString(Body, '_SYSTEMD_UNIT') as unit, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', 'info') as level, substring(${msg}, 1, 400) as message FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') IN ('supabase-db.service', 'supabase-auth.service', 'supabase-rest.service', 'supabase-storage.service', 'supabase-meta.service', 'supabase-realtime.service', 'supabase-studio.service', 'supabase-imgproxy.service') AND ${isErr} AND ${tfLog} ORDER BY Timestamp DESC LIMIT 200";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  10. Kanidm / Identity
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # sovereign IdP. WebAuthn/passkey-first, OIDC provider for the fleet.
  # kanidm emits structured JSON logs. Litestream replicates SQLite → R2.
  kanidm-identity = {
    title = "Kanidm / Identity";
    uid = "kanidm-identity";
    schemaVersion = 39;
    refresh = "1m";
    time = {
      from = "now-6h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "kanidm"
      "identity"
    ];
    panels = [

      # ── row: health ──────────────────────────────────────────────────────────
      (row {
        id = 100;
        title = "Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Kanidm logs (6h)";
        x = 0;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'kanidm.service' AND ${tfLog}";
      })
      (stat {
        id = 2;
        title = "Kanidm errors";
        x = 4;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'kanidm.service' AND ${isErr} AND ${tfLog}";
      })
      (stat {
        id = 3;
        title = "Auth attempts";
        x = 8;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'kanidm.service' AND (Body LIKE '%auth%' OR Body LIKE '%credential%' OR Body LIKE '%passkey%') AND ${tfLog}";
      })
      (stat {
        id = 4;
        title = "OIDC flows";
        x = 12;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'kanidm.service' AND (Body LIKE '%oauth2%' OR Body LIKE '%openid%' OR Body LIKE '%authorization_code%') AND ${tfLog}";
      })
      (stat {
        id = 5;
        title = "Litestream errors";
        x = 16;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'litestream.service' AND ${isErr} AND ${tfLog}";
      })
      (stat {
        id = 6;
        title = "Litestream WAL syncs";
        x = 20;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'litestream.service' AND (Body LIKE '%wal%' OR Body LIKE '%snapshot%' OR Body LIKE '%sync%') AND ${tfLog}";
        description = "replication events (WAL segment uploads, snapshots)";
      })

      # ── row: auth activity ───────────────────────────────────────────────────
      (row {
        id = 101;
        title = "Authentication";
        y = 5;
      })

      (panel {
        id = 10;
        title = "Kanidm log volume by severity";
        x = 0;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'kanidm.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 11;
        title = "Auth event breakdown";
        x = 12;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%passkey%' OR Body LIKE '%webauthn%', 'passkey', Body LIKE '%password%' OR Body LIKE '%credential%', 'password', Body LIKE '%oauth2%' OR Body LIKE '%openid%', 'oauth2', Body LIKE '%token%', 'token', 'other_auth') as method, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'kanidm.service' AND (Body LIKE '%auth%' OR Body LIKE '%credential%' OR Body LIKE '%passkey%' OR Body LIKE '%token%' OR Body LIKE '%oauth2%' OR Body LIKE '%openid%' OR Body LIKE '%webauthn%' OR Body LIKE '%password%') AND ${tfLog} GROUP BY time, method ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
        description = "auth flow classification: passkey, password, oauth2, token exchange";
      })

      # ── row: OIDC ───────────────────────────────────────────────────────────
      (row {
        id = 102;
        title = "OIDC / OAuth2";
        y = 14;
      })

      (panel {
        id = 12;
        title = "OIDC authorization events";
        x = 0;
        y = 15;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'kanidm.service' AND (Body LIKE '%authorization_code%' OR Body LIKE '%oauth2%consent%' OR Body LIKE '%token_exchange%') AND ${tfLog} GROUP BY time ORDER BY time";
        description = "OIDC consent/authorize/token flows (Forgejo SSO, future Grafana SSO)";
      })
      (panel {
        id = 13;
        title = "Failed auth attempts";
        x = 12;
        y = 15;
        w = 12;
        h = 8;
        unit = "short";
        thresholds = thresholdErrors;
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'kanidm.service' AND (Body LIKE '%invalid%' OR Body LIKE '%denied%' OR Body LIKE '%failed%' OR Body LIKE '%reject%') AND ${isWarn} AND ${tfLog} GROUP BY time ORDER BY time";
        description = "failed logins, denied access, rejected credentials. watch for brute-force.";
      })

      # ── row: Litestream ──────────────────────────────────────────────────────
      (row {
        id = 103;
        title = "Litestream (SQLite → R2)";
        y = 23;
      })

      (panel {
        id = 20;
        title = "Litestream log volume";
        x = 0;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'litestream.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 21;
        title = "Replication events (WAL sync / snapshot)";
        x = 12;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%snapshot%', 'snapshot', Body LIKE '%wal%', 'wal_sync', 'other') as event, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'litestream.service' AND (Body LIKE '%wal%' OR Body LIKE '%snapshot%' OR Body LIKE '%sync%') AND ${tfLog} GROUP BY time, event ORDER BY time";
        description = "WAL segments shipped to R2. gaps = replication lag.";
      })

      # ── row: errors ──────────────────────────────────────────────────────────
      (row {
        id = 104;
        title = "Errors & Audit";
        y = 32;
      })

      (table {
        id = 30;
        title = "Kanidm errors & warnings";
        x = 0;
        y = 33;
        w = 24;
        h = 8;
        sql = "SELECT Timestamp, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', 'info') as level, substring(${msg}, 1, 400) as message FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'kanidm.service' AND ${isWarn} AND ${tfLog} ORDER BY Timestamp DESC LIMIT 100";
      })
      (table {
        id = 31;
        title = "Litestream errors";
        x = 0;
        y = 41;
        w = 24;
        h = 8;
        sql = "SELECT Timestamp, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', 'info') as level, substring(${msg}, 1, 400) as message FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'litestream.service' AND ${isErr} AND ${tfLog} ORDER BY Timestamp DESC LIMIT 50";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  11. Forgejo (Git Forge)
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # git forge with prometheus metrics (:3200/metrics) + structured journal logs.
  # metrics enabled: Go runtime, gitea_* counters, issue/PR gauges.
  forgejo-activity = {
    title = "Forgejo (Git Forge)";
    uid = "forgejo-activity";
    schemaVersion = 39;
    refresh = "1m";
    time = {
      from = "now-6h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "forgejo"
      "git"
    ];
    panels = [

      # ── row: health ──────────────────────────────────────────────────────────
      (row {
        id = 100;
        title = "Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Goroutines";
        x = 0;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'go_goroutines' AND ${host} = 'watchtower' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 2;
        title = "Heap alloc";
        x = 4;
        y = 1;
        w = 4;
        h = 4;
        unit = "bytes";
        sql = "SELECT avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'go_memstats_heap_alloc_bytes' AND ${host} = 'watchtower' AND TimeUnix > now() - INTERVAL 2 MINUTE";
      })
      (stat {
        id = 3;
        title = "Errors (6h)";
        x = 8;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'forgejo.service' AND ${isErr} AND ${tfLog}";
      })
      (stat {
        id = 4;
        title = "Git pushes (6h)";
        x = 12;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE Body LIKE '%git-receive-pack%' AND ${tfLog}";
      })
      (stat {
        id = 5;
        title = "Git fetches (6h)";
        x = 16;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE Body LIKE '%git-upload-pack%' AND ${tfLog}";
      })
      (stat {
        id = 6;
        title = "HTTP requests/min";
        x = 20;
        y = 1;
        w = 4;
        h = 4;
        unit = "reqps";
        sql = "SELECT sum(rate) / 60 as value FROM (SELECT runningDifference(Value) as rate FROM otel.otel_metrics_sum WHERE MetricName = 'process_open_fds' AND ${host} = 'watchtower' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0";
        description = "approximation from process metrics";
      })

      # ── row: Go runtime ─────────────────────────────────────────────────────
      (row {
        id = 101;
        title = "Go Runtime";
        y = 5;
      })

      (panel {
        id = 10;
        title = "Goroutines";
        x = 0;
        y = 6;
        w = 8;
        h = 8;
        sql = "SELECT TimeUnix as time, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName = 'go_goroutines' AND ${host} = 'watchtower' AND ${tf} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 11;
        title = "Heap memory (alloc / sys)";
        x = 8;
        y = 6;
        w = 8;
        h = 8;
        unit = "bytes";
        sql = "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM otel.otel_metrics_gauge WHERE MetricName IN ('go_memstats_heap_alloc_bytes', 'go_memstats_heap_sys_bytes') AND ${host} = 'watchtower' AND ${tf} GROUP BY time, metric ORDER BY time";
      })
      (panel {
        id = 12;
        title = "Process CPU seconds/interval";
        x = 16;
        y = 6;
        w = 8;
        h = 8;
        unit = "s";
        sql = "SELECT TimeUnix as time, runningDifference(Value) as value FROM otel.otel_metrics_sum WHERE MetricName = 'process_cpu_seconds_total' AND ${host} = 'watchtower' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time";
        description = "process CPU seconds consumed per interval";
      })

      # ── row: git operations ──────────────────────────────────────────────────
      (row {
        id = 102;
        title = "Git Operations";
        y = 14;
      })

      (panel {
        id = 20;
        title = "Git push/fetch rate";
        x = 0;
        y = 15;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%git-receive-pack%', 'push', Body LIKE '%git-upload-pack%', 'fetch', 'other') as op, count() as value FROM otel.otel_logs WHERE (Body LIKE '%git-receive-pack%' OR Body LIKE '%git-upload-pack%') AND ${tfLog} GROUP BY time, op ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })
      (panel {
        id = 21;
        title = "SSH vs HTTP git traffic";
        x = 12;
        y = 15;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%SSH%' OR Body LIKE '%ssh%', 'ssh', Body LIKE '%HTTP%' OR Body LIKE '%http%', 'http', 'unknown') as proto, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'forgejo.service' AND (Body LIKE '%git-%pack%' OR Body LIKE '%refs/%') AND ${tfLog} GROUP BY time, proto ORDER BY time";
      })

      # ── row: log analysis ────────────────────────────────────────────────────
      (row {
        id = 103;
        title = "Logs";
        y = 23;
      })

      (panel {
        id = 30;
        title = "Forgejo log volume by severity";
        x = 0;
        y = 24;
        w = 24;
        h = 6;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'forgejo.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })

      # ── row: errors ──────────────────────────────────────────────────────────
      (row {
        id = 104;
        title = "Errors & Activity";
        y = 30;
      })

      (table {
        id = 40;
        title = "Forgejo errors";
        x = 0;
        y = 31;
        w = 24;
        h = 8;
        sql = "SELECT Timestamp, substring(${msg}, 1, 400) as message FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'forgejo.service' AND ${isErr} AND ${tfLog} ORDER BY Timestamp DESC LIMIT 50";
      })
      (table {
        id = 41;
        title = "Recent git activity";
        x = 0;
        y = 39;
        w = 24;
        h = 8;
        sql = "SELECT Timestamp, substring(${msg}, 1, 400) as activity FROM otel.otel_logs WHERE (Body LIKE '%git-receive-pack%' OR Body LIKE '%git-upload-pack%' OR Body LIKE '%refs/heads%') AND ${tfLog} ORDER BY Timestamp DESC LIMIT 50";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  12. NativeLink (Remote Execution)
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # remote execution: scheduler (watchtower), CAS shards (fleet), workers (fleet).
  # topology from the Dhall registry. all components emit structured logs.
  nativelink = {
    title = "NativeLink (Remote Execution)";
    uid = "nativelink";
    schemaVersion = 39;
    refresh = "1m";
    time = {
      from = "now-6h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "nativelink"
      "build"
    ];
    templating.list = [ hostVarAll ];
    panels = [

      # ── row: health ──────────────────────────────────────────────────────────
      (row {
        id = 100;
        title = "Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Log lines (6h)";
        x = 0;
        y = 1;
        w = 6;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'nativelink.service' AND ${tfLog}";
      })
      (stat {
        id = 2;
        title = "Errors (6h)";
        x = 6;
        y = 1;
        w = 6;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'nativelink.service' AND ${isErr} AND ${tfLog}";
      })
      (stat {
        id = 3;
        title = "Active nodes";
        x = 12;
        y = 1;
        w = 6;
        h = 4;
        sql = "SELECT uniq(${host}) as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'nativelink.service' AND Timestamp > now() - INTERVAL 1 HOUR";
      })
      (stat {
        id = 4;
        title = "Lines/min (rate)";
        x = 18;
        y = 1;
        w = 6;
        h = 4;
        sql = "SELECT count() / 360 as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'nativelink.service' AND ${tfLog}";
      })
      (stat {
        id = 5;
        title = "Active nodes";
        x = 16;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT uniq(${host}) as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'nativelink%' AND Timestamp > now() - INTERVAL 1 HOUR";
      })
      (stat {
        id = 6;
        title = "Build actions (est)";
        x = 20;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'nativelink%' AND (Body LIKE '%execute%' OR Body LIKE '%action%' OR Body LIKE '%running%') AND ${tfLog}";
        description = "estimated build action count from worker logs";
      })

      # ── row: scheduler ───────────────────────────────────────────────────────
      (row {
        id = 101;
        title = "Scheduler";
        y = 5;
      })

      (panel {
        id = 10;
        title = "Scheduler log volume";
        x = 0;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'nativelink%' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 11;
        title = "Scheduler connection events";
        x = 12;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%connect%', 'connect', Body LIKE '%disconnect%' OR Body LIKE '%drop%', 'disconnect', Body LIKE '%queue%' OR Body LIKE '%schedule%', 'schedule', 'other') as event, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'nativelink%' AND (Body LIKE '%connect%' OR Body LIKE '%disconnect%' OR Body LIKE '%queue%' OR Body LIKE '%schedule%' OR Body LIKE '%drop%') AND ${tfLog} GROUP BY time, event ORDER BY time";
      })

      # ── row: workers ─────────────────────────────────────────────────────────
      (row {
        id = 102;
        title = "Workers";
        y = 14;
      })

      (panel {
        id = 20;
        title = "Worker log volume by host";
        x = 0;
        y = 15;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, ${host} as node, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'nativelink%' AND ${tfLog} AND ${hostFilter} GROUP BY time, node ORDER BY time";
      })
      (panel {
        id = 21;
        title = "Worker execution events";
        x = 12;
        y = 15;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%execute%' OR Body LIKE '%running%', 'executing', Body LIKE '%complete%' OR Body LIKE '%finish%', 'completed', Body LIKE '%error%' OR Body LIKE '%fail%', 'failed', 'other') as status, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'nativelink%' AND (Body LIKE '%execute%' OR Body LIKE '%running%' OR Body LIKE '%complete%' OR Body LIKE '%finish%' OR Body LIKE '%error%' OR Body LIKE '%fail%') AND ${tfLog} GROUP BY time, status ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })

      # ── row: CAS ─────────────────────────────────────────────────────────────
      (row {
        id = 103;
        title = "CAS (Content Addressable Storage)";
        y = 23;
      })

      (panel {
        id = 30;
        title = "CAS log volume by host";
        x = 0;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, ${host} as node, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'nativelink%' AND ${tfLog} AND ${hostFilter} GROUP BY time, node ORDER BY time";
      })
      (panel {
        id = 31;
        title = "CAS operations (get/put/contains)";
        x = 12;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%get%' OR Body LIKE '%read%' OR Body LIKE '%fetch%', 'get', Body LIKE '%put%' OR Body LIKE '%write%' OR Body LIKE '%store%', 'put', Body LIKE '%contain%' OR Body LIKE '%exist%', 'contains', 'other') as op, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'nativelink%' AND (Body LIKE '%get%' OR Body LIKE '%put%' OR Body LIKE '%read%' OR Body LIKE '%write%' OR Body LIKE '%contain%' OR Body LIKE '%exist%' OR Body LIKE '%fetch%' OR Body LIKE '%store%') AND ${tfLog} GROUP BY time, op ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })

      # ── row: errors ──────────────────────────────────────────────────────────
      (row {
        id = 104;
        title = "Errors";
        y = 32;
      })

      (table {
        id = 40;
        title = "All NativeLink errors";
        x = 0;
        y = 33;
        w = 24;
        h = 10;
        sql = "SELECT Timestamp, ${host} as host, JSONExtractString(Body, '_SYSTEMD_UNIT') as unit, substring(${msg}, 1, 400) as message FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'nativelink%' AND ${isErr} AND ${tfLog} ORDER BY Timestamp DESC LIMIT 100";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  13. Attic (Binary Cache)
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # nix binary cache. atticd on watchtower (primary) + replicas on fleet.
  # serves NARs over HTTP, backed by PG17 for metadata + S3/R2 for chunks.
  attic = {
    title = "Attic (Binary Cache)";
    uid = "attic";
    schemaVersion = 39;
    refresh = "1m";
    time = {
      from = "now-6h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "attic"
      "nix"
    ];
    templating.list = [ hostVarAll ];
    panels = [

      # ── row: health ──────────────────────────────────────────────────────────
      (row {
        id = 100;
        title = "Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Attic logs (6h)";
        x = 0;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND ${tfLog}";
      })
      (stat {
        id = 2;
        title = "Errors";
        x = 4;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND ${isErr} AND ${tfLog}";
      })
      (stat {
        id = 3;
        title = "NAR uploads";
        x = 8;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND (Body LIKE '%upload%' OR Body LIKE '%PUT%' OR Body LIKE '%push%') AND ${tfLog}";
      })
      (stat {
        id = 4;
        title = "NAR downloads";
        x = 12;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND (Body LIKE '%GET%' OR Body LIKE '%serve%' OR Body LIKE '%download%') AND ${tfLog}";
      })
      (stat {
        id = 5;
        title = "Active nodes";
        x = 16;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT uniq(${host}) as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND Timestamp > now() - INTERVAL 1 HOUR";
      })
      (stat {
        id = 6;
        title = "Cache misses (404)";
        x = 20;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND (Body LIKE '%404%' OR Body LIKE '%not found%') AND ${tfLog}";
      })

      # ── row: traffic ─────────────────────────────────────────────────────────
      (row {
        id = 101;
        title = "Traffic";
        y = 5;
      })

      (panel {
        id = 10;
        title = "Request volume by node";
        x = 0;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, ${host} as node, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND ${tfLog} AND ${hostFilter} GROUP BY time, node ORDER BY time";
      })
      (panel {
        id = 11;
        title = "Operation breakdown";
        x = 12;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%upload%' OR Body LIKE '%PUT%' OR Body LIKE '%push%', 'upload', Body LIKE '%GET%nar%' OR Body LIKE '%serve%' OR Body LIKE '%download%', 'download', Body LIKE '%narinfo%' OR Body LIKE '%HEAD%', 'narinfo_check', 'other') as op, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND (Body LIKE '%upload%' OR Body LIKE '%PUT%' OR Body LIKE '%GET%' OR Body LIKE '%HEAD%' OR Body LIKE '%serve%' OR Body LIKE '%push%' OR Body LIKE '%download%' OR Body LIKE '%narinfo%') AND ${tfLog} GROUP BY time, op ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })

      # ── row: logs ────────────────────────────────────────────────────────────
      (row {
        id = 102;
        title = "Logs";
        y = 14;
      })

      (panel {
        id = 20;
        title = "Log volume by severity";
        x = 0;
        y = 15;
        w = 24;
        h = 6;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })

      # ── row: errors ──────────────────────────────────────────────────────────
      (row {
        id = 103;
        title = "Errors";
        y = 21;
      })

      (table {
        id = 30;
        title = "Attic errors";
        x = 0;
        y = 22;
        w = 24;
        h = 10;
        sql = "SELECT Timestamp, ${host} as host, substring(${msg}, 1, 400) as message FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'atticd.service' AND ${isErr} AND ${tfLog} ORDER BY Timestamp DESC LIMIT 100";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  14. OCI Registry (Zot)
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # OCI image registry. fronted by nginx. blobs stored in R2.
  # zot emits JSON-structured access logs with method, path, status, latency.
  oci-registry = {
    title = "OCI Registry (Zot)";
    uid = "oci-registry";
    schemaVersion = 39;
    refresh = "1m";
    time = {
      from = "now-6h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "registry"
      "oci"
    ];
    panels = [

      # ── row: health ──────────────────────────────────────────────────────────
      (row {
        id = 100;
        title = "Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "Zot logs (6h)";
        x = 0;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND ${tfLog}";
      })
      (stat {
        id = 2;
        title = "Errors";
        x = 4;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND ${isErr} AND ${tfLog}";
      })
      (stat {
        id = 3;
        title = "Pushes (PUT)";
        x = 8;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND Body LIKE '%PUT%' AND ${tfLog}";
      })
      (stat {
        id = 4;
        title = "Pulls (GET)";
        x = 12;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND Body LIKE '%GET%' AND Body LIKE '%blobs%' AND ${tfLog}";
      })
      (stat {
        id = 5;
        title = "Manifests served";
        x = 16;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND Body LIKE '%manifests%' AND ${tfLog}";
      })
      (stat {
        id = 6;
        title = "4xx/5xx responses";
        x = 20;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND (Body LIKE '%\" 4%' OR Body LIKE '%\" 5%') AND ${tfLog}";
      })

      # ── row: traffic ─────────────────────────────────────────────────────────
      (row {
        id = 101;
        title = "Traffic";
        y = 5;
      })

      (panel {
        id = 10;
        title = "Request volume";
        x = 0;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND ${tfLog} GROUP BY time ORDER BY time";
      })
      (panel {
        id = 11;
        title = "Operations (push/pull/manifest/catalog)";
        x = 12;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%PUT%' AND Body LIKE '%blobs%', 'blob_push', Body LIKE '%PUT%' AND Body LIKE '%manifests%', 'manifest_push', Body LIKE '%GET%' AND Body LIKE '%blobs%', 'blob_pull', Body LIKE '%GET%' AND Body LIKE '%manifests%', 'manifest_pull', Body LIKE '%GET%' AND Body LIKE '%tags%', 'tag_list', 'other') as op, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND (Body LIKE '%PUT%' OR Body LIKE '%GET%') AND ${tfLog} GROUP BY time, op ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })

      # ── row: logs ────────────────────────────────────────────────────────────
      (row {
        id = 102;
        title = "Logs";
        y = 14;
      })

      (panel {
        id = 20;
        title = "Log volume by severity";
        x = 0;
        y = 15;
        w = 24;
        h = 6;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })

      # ── row: errors ──────────────────────────────────────────────────────────
      (row {
        id = 103;
        title = "Errors";
        y = 21;
      })

      (table {
        id = 30;
        title = "Registry errors & 4xx/5xx";
        x = 0;
        y = 22;
        w = 24;
        h = 10;
        sql = "SELECT Timestamp, substring(${msg}, 1, 400) as message FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'zot.service' AND (${isErr} OR Body LIKE '%\" 4%' OR Body LIKE '%\" 5%') AND ${tfLog} ORDER BY Timestamp DESC LIMIT 100";
      })
    ];
  };

  # ════════════════════════════════════════════════════════════════════════════════
  #  15. Backup & PITR
  # ════════════════════════════════════════════════════════════════════════════════
  #
  # are backups running? when was the last successful one?
  # pgbackrest (PG17 PITR → R2), litestream (Kanidm SQLite → R2),
  # restic (forgejo repos, kanidm, pg dump → R2).
  backup-pitr = {
    title = "Backup & PITR";
    uid = "backup-pitr";
    schemaVersion = 39;
    refresh = "5m";
    time = {
      from = "now-24h";
      to = "now";
    };
    timezone = "browser";
    editable = true;
    tags = [
      "backup"
      "pitr"
    ];
    templating.list = [ hostVarAll ];
    panels = [

      # ── row: health ──────────────────────────────────────────────────────────
      (row {
        id = 100;
        title = "Health";
        y = 0;
      })

      (stat {
        id = 1;
        title = "pgbackrest events";
        x = 0;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'pgbackrest%' AND ${tfLog}";
      })
      (stat {
        id = 2;
        title = "pgbackrest errors";
        x = 4;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'pgbackrest%' AND ${isErr} AND ${tfLog}";
      })
      (stat {
        id = 3;
        title = "Restic events";
        x = 8;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'restic%' AND ${tfLog}";
      })
      (stat {
        id = 4;
        title = "Restic errors";
        x = 12;
        y = 1;
        w = 4;
        h = 4;
        thresholds = thresholdErrors;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'restic%' AND ${isErr} AND ${tfLog}";
      })
      (stat {
        id = 5;
        title = "Litestream events";
        x = 16;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'litestream.service' AND ${tfLog}";
      })
      (stat {
        id = 6;
        title = "PG dump events";
        x = 20;
        y = 1;
        w = 4;
        h = 4;
        sql = "SELECT count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-db-dump.service' AND ${tfLog}";
      })

      # ── row: pgbackrest ──────────────────────────────────────────────────────
      (row {
        id = 101;
        title = "pgBackRest (PG17 PITR → R2)";
        y = 5;
      })

      (panel {
        id = 10;
        title = "pgBackRest log activity";
        x = 0;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'pgbackrest%' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 11;
        title = "WAL archive events (from PG17 logs)";
        x = 12;
        y = 6;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-db.service' AND (Body LIKE '%archive%' OR Body LIKE '%wal%') AND ${tfLog} GROUP BY time ORDER BY time";
        description = "WAL segment archive commands logged by PG17. steady rate = healthy archiving.";
      })

      # ── row: restic ──────────────────────────────────────────────────────────
      (row {
        id = 102;
        title = "Restic (File Backups → R2)";
        y = 14;
      })

      (panel {
        id = 20;
        title = "Restic backup activity by host";
        x = 0;
        y = 15;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, ${host} as node, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'restic%' AND ${tfLog} AND ${hostFilter} GROUP BY time, node ORDER BY time";
      })
      (panel {
        id = 21;
        title = "Restic operations (backup/check/prune)";
        x = 12;
        y = 15;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%backup%' OR Body LIKE '%snapshot%', 'backup', Body LIKE '%check%' OR Body LIKE '%verify%', 'check', Body LIKE '%prune%' OR Body LIKE '%forget%', 'prune', 'other') as op, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'restic%' AND (Body LIKE '%backup%' OR Body LIKE '%snapshot%' OR Body LIKE '%check%' OR Body LIKE '%prune%' OR Body LIKE '%forget%' OR Body LIKE '%verify%') AND ${tfLog} GROUP BY time, op ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 60;
        };
      })

      # ── row: litestream ──────────────────────────────────────────────────────
      (row {
        id = 103;
        title = "Litestream (Kanidm SQLite → R2)";
        y = 23;
      })

      (panel {
        id = 30;
        title = "Litestream replication events";
        x = 0;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'litestream.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
      })
      (panel {
        id = 31;
        title = "PG logical dump activity";
        x = 12;
        y = 24;
        w = 12;
        h = 8;
        unit = "short";
        sql = "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug') as severity, count() as value FROM otel.otel_logs WHERE JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-db-dump.service' AND ${tfLog} GROUP BY time, severity ORDER BY time";
        fieldConfig = {
          defaults.custom.stacking = {
            mode = "normal";
            group = "A";
          };
          defaults.custom.fillOpacity = 80;
        };
        description = "daily pg_dumpall: independent safety net alongside pgbackrest PITR";
      })

      # ── row: errors ──────────────────────────────────────────────────────────
      (row {
        id = 104;
        title = "All Backup Errors";
        y = 32;
      })

      (table {
        id = 40;
        title = "Backup errors (all systems)";
        x = 0;
        y = 33;
        w = 24;
        h = 10;
        sql = "SELECT Timestamp, ${host} as host, JSONExtractString(Body, '_SYSTEMD_UNIT') as unit, substring(${msg}, 1, 400) as message FROM otel.otel_logs WHERE (JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'pgbackrest%' OR JSONExtractString(Body, '_SYSTEMD_UNIT') LIKE 'restic%' OR JSONExtractString(Body, '_SYSTEMD_UNIT') = 'litestream.service' OR JSONExtractString(Body, '_SYSTEMD_UNIT') = 'supabase-db-dump.service') AND ${isErr} AND ${tfLog} ORDER BY Timestamp DESC LIMIT 100";
      })
    ];
  };
}
