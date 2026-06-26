--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // grafana // panels
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  Reusable panel constructors. Each takes the minimum necessary args and produces
--  a Panel with sensible defaults. Compose dashboards from these, not raw JSON.

let T = ./types.dhall

-- a clickhouse SQL target with time_series format
let chQuery =
      \(sql : Text) ->
        T.Target::{ rawSql = sql, format = "time_series" }

-- a clickhouse SQL target for table/logs
let chTable =
      \(sql : Text) ->
        T.Target::{ rawSql = sql, format = "table" }

let chLogs =
      \(sql : Text) ->
        T.Target::{ rawSql = sql, format = "logs" }

-- ── host metrics panels ──────────────────────────────────────────────────────

let cpuUsage =
      T.Panel::{
      , title = "CPU usage"
      , type = T.PanelType.TimeSeries
      , unit = T.Unit.Percent0to1
      , width = 8
      , height = 8
      , targets =
        [ chQuery
            ''
            SELECT
              Timestamp as time,
              ResourceAttributes['host.name'] as host,
              avg(Value) as value
            FROM otel.otel_metrics
            WHERE MetricName = 'system.cpu.utilization'
              AND $__timeFilter(Timestamp)
            GROUP BY time, host
            ORDER BY time
            ''
        ]
      }

let memoryUsage =
      T.Panel::{
      , title = "Memory usage"
      , type = T.PanelType.TimeSeries
      , unit = T.Unit.Bytes
      , width = 8
      , height = 8
      , targets =
        [ chQuery
            ''
            SELECT
              Timestamp as time,
              ResourceAttributes['host.name'] as host,
              avg(Value) as value
            FROM otel.otel_metrics
            WHERE MetricName = 'system.memory.usage'
              AND Attributes['state'] = 'used'
              AND $__timeFilter(Timestamp)
            GROUP BY time, host
            ORDER BY time
            ''
        ]
      }

let diskIO =
      T.Panel::{
      , title = "Disk I/O"
      , type = T.PanelType.TimeSeries
      , unit = T.Unit.BytesPerSec
      , width = 8
      , height = 8
      , targets =
        [ chQuery
            ''
            SELECT
              Timestamp as time,
              ResourceAttributes['host.name'] as host,
              avg(Value) as value
            FROM otel.otel_metrics
            WHERE MetricName IN ('system.disk.io')
              AND $__timeFilter(Timestamp)
            GROUP BY time, host
            ORDER BY time
            ''
        ]
      }

let networkTraffic =
      T.Panel::{
      , title = "Network traffic"
      , type = T.PanelType.TimeSeries
      , unit = T.Unit.BytesPerSec
      , width = 12
      , height = 8
      , targets =
        [ chQuery
            ''
            SELECT
              Timestamp as time,
              ResourceAttributes['host.name'] as host,
              Attributes['device'] as device,
              avg(Value) as value
            FROM otel.otel_metrics
            WHERE MetricName = 'system.network.io'
              AND Attributes['direction'] = 'transmit'
              AND $__timeFilter(Timestamp)
            GROUP BY time, host, device
            ORDER BY time
            ''
        ]
      }

let loadAverage =
      T.Panel::{
      , title = "Load average (1m)"
      , type = T.PanelType.TimeSeries
      , unit = T.Unit.Short
      , width = 12
      , height = 8
      , targets =
        [ chQuery
            ''
            SELECT
              Timestamp as time,
              ResourceAttributes['host.name'] as host,
              avg(Value) as value
            FROM otel.otel_metrics
            WHERE MetricName = 'system.cpu.load_average.1m'
              AND $__timeFilter(Timestamp)
            GROUP BY time, host
            ORDER BY time
            ''
        ]
      }

-- ── log panels ───────────────────────────────────────────────────────────────

let recentLogs =
      T.Panel::{
      , title = "Recent logs"
      , type = T.PanelType.Logs
      , unit = T.Unit.None
      , width = 24
      , height = 12
      , targets =
        [ chLogs
            ''
            SELECT
              Timestamp as time,
              Body as content,
              SeverityText as level,
              ResourceAttributes['host.name'] as host,
              ResourceAttributes['service.name'] as service
            FROM otel.otel_logs
            WHERE $__timeFilter(Timestamp)
              AND ($host = '''''' OR ResourceAttributes['host.name'] = $host)
            ORDER BY Timestamp DESC
            LIMIT 500
            ''
        ]
      }

let errorLogs =
      T.Panel::{
      , title = "Errors (last hour)"
      , type = T.PanelType.Table
      , unit = T.Unit.None
      , width = 24
      , height = 10
      , targets =
        [ chTable
            ''
            SELECT
              Timestamp,
              ResourceAttributes['host.name'] as host,
              SeverityText as level,
              Body as message
            FROM otel.otel_logs
            WHERE SeverityNumber >= 17
              AND $__timeFilter(Timestamp)
            ORDER BY Timestamp DESC
            LIMIT 100
            ''
        ]
      }

-- ── service-specific panels ──────────────────────────────────────────────────

let clickhouseQueries =
      T.Panel::{
      , title = "ClickHouse queries/sec"
      , type = T.PanelType.TimeSeries
      , unit = T.Unit.OpsPerSec
      , width = 12
      , height = 8
      , targets =
        [ chQuery
            ''
            SELECT
              Timestamp as time,
              avg(Value) as value
            FROM otel.otel_metrics
            WHERE MetricName = 'ClickHouseProfileEvents_Query'
              AND $__timeFilter(Timestamp)
            GROUP BY time
            ORDER BY time
            ''
        ]
      }

let corednsQueries =
      T.Panel::{
      , title = "CoreDNS queries/sec"
      , type = T.PanelType.TimeSeries
      , unit = T.Unit.OpsPerSec
      , width = 12
      , height = 8
      , targets =
        [ chQuery
            ''
            SELECT
              Timestamp as time,
              avg(Value) as value
            FROM otel.otel_metrics
            WHERE MetricName = 'coredns_dns_requests_total'
              AND $__timeFilter(Timestamp)
            GROUP BY time
            ORDER BY time
            ''
        ]
      }

in  { chQuery
    , chTable
    , chLogs
    , cpuUsage
    , memoryUsage
    , diskIO
    , networkTraffic
    , loadAverage
    , recentLogs
    , errorLogs
    , clickhouseQueries
    , corednsQueries
    }
