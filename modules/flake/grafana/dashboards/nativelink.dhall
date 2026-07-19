-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                     // hypermodern // grafana // nativelink
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
let T = ../schema/types.dhall

let S = ../schema/sql.dhall

let P = ../schema/panels.dhall

let R = ../schema/render.dhall

let hostVar =
      T.Variable::{
      , name = "host"
      , label = "Host"
      , type = T.VariableType.Query
      , query =
          "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1"
      , includeAll = True
      }

let svc = "nativelink.service"

let cacheSvc = "nativelink-nix-cache.service"

let pushFailFilter =
      "${S.unit} = 'nix-daemon.service' AND Body LIKE '%nativelink-nix-cache: push failed%'"

let dashboard =
      T.Dashboard::{
      , title = "NativeLink (Cache + Remote Execution)"
      , uid = "nativelink"
      , tags = [ "nativelink", "build", "nix" ]
      , refresh = "1m"
      , timeFrom = "now-6h"
      , variables = [ hostVar ]
      , rows =
        [ T.Row::{
          , title = "Nix Cache — Health"
          , panels =
            [ P.statLogs "Log lines" cacheSvc
            , P.statErrors "Errors" cacheSvc
            , P.stat
                "Uploads"
                "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = '${cacheSvc}' AND (Body LIKE '%PUT%' OR Body LIKE '%upload%' OR Body LIKE '%push%') AND ${S.tfLog}"
            , P.stat
                "Downloads"
                "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = '${cacheSvc}' AND (Body LIKE '%GET%nar%' OR Body LIKE '%serve%' OR Body LIKE '%download%') AND ${S.tfLog}"
            , P.stat
                "Narinfo"
                "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = '${cacheSvc}' AND (Body LIKE '%narinfo%' OR Body LIKE '%HEAD%') AND ${S.tfLog}"
            , P.stat
                "404s"
                "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = '${cacheSvc}' AND (Body LIKE '%404%' OR Body LIKE '%not found%') AND ${S.tfLog}"
            ]
          }
        , T.Row::{
          , title = "Nix Cache — Traffic"
          , panels =
            [ P.timeseries
                "By node"
                T.Unit.Short
                "SELECT toStartOfFiveMinutes(Timestamp) as time, ${S.host} as node, count() as value FROM ${S.logs} WHERE ${S.unit} = '${cacheSvc}' AND ${S.tfLog} AND ${S.hostFilter} GROUP BY time, node ORDER BY time"
            ,     P.timeseriesStacked
                    "Operations"
                    T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%PUT%' OR Body LIKE '%upload%' OR Body LIKE '%push%', 'upload', Body LIKE '%GET%nar%' OR Body LIKE '%serve%' OR Body LIKE '%download%', 'download', Body LIKE '%narinfo%' OR Body LIKE '%HEAD%', 'narinfo', 'other') as op, count() as value FROM ${S.logs} WHERE ${S.unit} = '${cacheSvc}' AND (Body LIKE '%PUT%' OR Body LIKE '%GET%' OR Body LIKE '%HEAD%' OR Body LIKE '%upload%' OR Body LIKE '%serve%' OR Body LIKE '%push%' OR Body LIKE '%download%' OR Body LIKE '%narinfo%') AND ${S.tfLog} GROUP BY time, op ORDER BY time"
              //  { fillOpacity = 60 }
            ]
          }
        , T.Row::{
          , title = "Nix Cache — Push Hook"
          , panels =
            [ P.stat
                "Push failures"
                "SELECT count() as value FROM ${S.logs} WHERE ${pushFailFilter} AND ${S.tfLog}"
            , P.table
                "Push failures"
                "SELECT Timestamp, ${S.host} as host, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${pushFailFilter} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 100"
            ]
          }
        , T.Row::{
          , title = "Remote Execution — Health"
          , panels =
            [ P.statLogs "Log lines" svc // { width = 6 }
            , P.statErrors "Errors" svc // { width = 6 }
            ,     P.stat
                    "Active nodes"
                    "SELECT uniq(${S.host}) as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND Timestamp > now() - INTERVAL 1 HOUR"
              //  { width = 6 }
            ,     P.stat
                    "Lines/min"
                    "SELECT count() / 360 as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND ${S.tfLog}"
              //  { width = 6 }
            ]
          }
        , T.Row::{
          , title = "Remote Execution — Activity"
          , panels =
            [ P.logVolume "Log volume" svc
            , P.timeseries
                "Events by host"
                T.Unit.Short
                "SELECT toStartOfFiveMinutes(Timestamp) as time, ${S.host} as node, count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'nativelink%' AND ${S.tfLog} AND ${S.hostFilter} GROUP BY time, node ORDER BY time"
            ]
          }
        , T.Row::{
          , title = "Remote Execution — CAS Read Tiers"
          , panels =
            [ P.stat
                "R2 (slow) read latency — ms"
                "SELECT round(sum(Sum) / greatest(sum(Count), 1)) as value FROM otel.otel_metrics_histogram WHERE MetricName = 'cache.operation.duration' AND Attributes['cache.operation.name'] = 'read' AND Attributes['cache.type'] = 'cas-slow' AND Count > 0 AND ${S.tf}"
            , P.stat
                "Fast tier (NVMe) read latency — ms"
                "SELECT round(sum(Sum) / greatest(sum(Count), 1)) as value FROM otel.otel_metrics_histogram WHERE MetricName = 'cache.operation.duration' AND Attributes['cache.operation.name'] = 'read' AND Attributes['cache.type'] = 'cas-fast' AND Count > 0 AND ${S.tf}"
            , P.stat
                "Reads served from fast tier — %"
                "SELECT round(100 * sumIf(v, tier = 'cas-fast') / greatest(sum(v), 1)) as value FROM (SELECT Attributes['cache.type'] as tier, max(Count) as v FROM otel.otel_metrics_histogram WHERE MetricName = 'cache.operation.duration' AND Attributes['cache.operation.name'] = 'read' AND Attributes['cache.operation.result'] = 'hit' AND ${S.tf} GROUP BY tier, ${S.host})"
            , P.timeseries
                "CAS read latency by tier"
                T.Unit.Milliseconds
                "SELECT toStartOfFiveMinutes(TimeUnix) as time, Attributes['cache.type'] as tier, round(avg(Sum / greatest(Count, 1)), 1) as value FROM otel.otel_metrics_histogram WHERE MetricName = 'cache.operation.duration' AND Attributes['cache.operation.name'] = 'read' AND Count > 0 AND ${S.tf} AND ${S.hostFilter} GROUP BY time, tier ORDER BY time"
            ]
          }
        , T.Row::{
          , title = "Remote Execution — Throughput"
          , panels =
            [ P.timeseries
                "Actions completed / s"
                T.Unit.Short
                "SELECT time, sum(rate) as value FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, extractGroups(MetricName, 'workers_workers_([0-9a-f_]+)_run_action_successes')[1] as w, runningDifference(max(Value)) / 30 as rate FROM ${S.gauge} WHERE MetricName LIKE 'nativelink_schedulers_%_run_action_successes' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, w ORDER BY w, time) WHERE rate >= 0 GROUP BY time ORDER BY time"
            , P.timeseriesStacked
                "Client CAS ops / s by result"
                T.Unit.Short
                ( S.rateBucketed
                    "cache.operations"
                    "Attributes['cache.type'] LIKE 'cas-%'"
                    "Attributes['cache.operation.result']"
                    "result"
                )
            , P.timeseriesStacked
                "Client CAS ops / s by kind"
                T.Unit.Short
                ( S.rateBucketed
                    "cache.operations"
                    "Attributes['cache.type'] LIKE 'cas-%'"
                    "Attributes['cache.operation.name']"
                    "kind"
                )
            ]
          }
        , T.Row::{
          , title = "CAS — Tier Performance"
          , panels =
            [ P.timeseries
                "Read throughput by tier"
                T.Unit.BytesPerSec
                ( S.rateBucketed
                    "cache.io"
                    "Attributes['cache.operation.name'] = 'read'"
                    "Attributes['cache.type']"
                    "tier"
                )
            , P.timeseries
                "Write throughput by tier"
                T.Unit.BytesPerSec
                ( S.rateBucketed
                    "cache.io"
                    "Attributes['cache.operation.name'] = 'write'"
                    "Attributes['cache.type']"
                    "tier"
                )
            , P.timeseries
                "Blob size (avg) by tier"
                T.Unit.Bytes
                "SELECT toStartOfFiveMinutes(TimeUnix) as time, Attributes['cache.type'] as tier, round(avg(Sum / greatest(Count, 1))) as value FROM otel.otel_metrics_histogram WHERE MetricName = 'cache.item.size' AND Count > 0 AND ${S.tf} AND ${S.hostFilter} GROUP BY time, tier ORDER BY time"
            ]
          }
        , T.Row::{
          , title = "Action Cache"
          , panels =
            [ P.stat
                "AC read hit rate — %"
                "SELECT round(100 * sumIf(v, res = 'hit') / greatest(sum(v), 1)) as value FROM (SELECT Attributes['cache.operation.result'] as res, max(Value) as v FROM ${S.sum} WHERE MetricName = 'cache.operations' AND Attributes['cache.type'] LIKE 'ac-%' AND Attributes['cache.operation.name'] = 'read' AND ${S.tf} GROUP BY res, ${S.host})"
            , P.timeseriesStacked
                "AC read ops / s by result"
                T.Unit.Short
                ( S.rateBucketed
                    "cache.operations"
                    "Attributes['cache.type'] LIKE 'ac-%' AND Attributes['cache.operation.name'] = 'read'"
                    "Attributes['cache.operation.result']"
                    "result"
                )
            , P.timeseries
                "AC op latency by result — ms"
                T.Unit.Milliseconds
                "SELECT toStartOfFiveMinutes(TimeUnix) as time, Attributes['cache.operation.result'] as result, round(avg(Sum / greatest(Count, 1)), 2) as value FROM otel.otel_metrics_histogram WHERE MetricName = 'cache.operation.duration' AND Attributes['cache.type'] LIKE 'ac-%' AND Count > 0 AND ${S.tf} AND ${S.hostFilter} GROUP BY time, result ORDER BY time"
            ]
          }
        , T.Row::{
          , title = "Scheduler & Workers (scraped /metrics)"
          , panels =
            [ P.stat
                "Connected workers"
                "SELECT count(DISTINCT extractGroups(MetricName, 'workers_workers_([0-9a-f_]+)_connected_timestamp')[1]) as value FROM ${S.gauge} WHERE MetricName LIKE 'nativelink_schedulers_%workers_workers_%_connected_timestamp' AND TimeUnix > now() - INTERVAL 2 MINUTE"
            , P.timeseries
                "Actions completed / s by worker"
                T.Unit.Short
                ( S.rateGaugeByExtract
                    "nativelink_schedulers_%_run_action_successes"
                    "workers_workers_([0-9a-f_]+)_run_action_successes"
                    "worker"
                )
            , P.timeseries
                "Action failures / s by worker"
                T.Unit.Short
                ( S.rateGaugeByExtract
                    "nativelink_schedulers_%_run_action_failures"
                    "workers_workers_([0-9a-f_]+)_run_action_failures"
                    "worker"
                )
            ]
          }
        , T.Row::{
          , title = "CAS — Fast-Tier Internals (scraped /metrics)"
          , panels =
            [ P.stat
                "CAS fast-tier fill — %"
                "SELECT round(100 * sum(fill) / greatest(sum(cap), 1), 1) as value FROM (SELECT ${S.host} as h, avgIf(Value, MetricName LIKE '%sum_store_size') as fill, avgIf(Value, MetricName LIKE '%max_bytes') as cap FROM ${S.gauge} WHERE MetricName IN ('nativelink_stores_CAS_LOCAL_fast_store_backend_evicting_map_sum_store_size', 'nativelink_stores_CAS_LOCAL_fast_store_backend_evicting_map_max_bytes') AND TimeUnix > now() - INTERVAL 2 MINUTE GROUP BY h)"
            , P.timeseries
                "Fast-tier fill by host"
                T.Unit.Bytes
                ( S.gaugeByHost
                    "nativelink_stores_CAS_LOCAL_fast_store_backend_evicting_map_sum_store_size"
                )
            , P.timeseries
                "Fast-tier inserts by host"
                T.Unit.BytesPerSec
                ( S.rateGaugeByHost
                    "nativelink_stores_CAS_LOCAL_fast_store_backend_evicting_map_lifetime_inserted_bytes"
                )
            , P.timeseries
                "Fast-tier evictions by host"
                T.Unit.BytesPerSec
                ( S.rateGaugeByHost
                    "nativelink_stores_CAS_LOCAL_fast_store_backend_evicting_map_evicted_bytes"
                )
            ]
          }
        , T.Row::{
          , title = "Errors (all nativelink units)"
          , panels =
            [ P.table
                "All errors"
                "SELECT Timestamp, ${S.host} as host, ${S.unit} as unit, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.unit} LIKE 'nativelink%' AND ${S.isErr} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 100"
            ]
          }
        ]
      }

in  R.renderDashboard dashboard
