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
      , query = S.hostInventory
      , includeAll = True
      }

-- Cumulative OTel histograms, per SERIES (host x process instance x group key):
-- delta of Count (and Sum) between 30 s buckets, resets clamped to 0. The fork
-- emits no per-tier latency or AC-specific metric (store.tier.* carries only
-- tier + direction/result), so the old cache.* panels are gone, not faked.
let histDeltas =
      \(metric : Text) ->
      \(groupKey : Text) ->
      \(alias : Text) ->
        "SELECT time, ${alias}, greatest(0, c - lagInFrame(c, 1, c) OVER w) as dc, greatest(0, s - lagInFrame(s, 1, s) OVER w) as ds FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${S.host} as h, ResourceAttributes['service.instance.id'] as inst, toString(Attributes) as a, ${groupKey} as ${alias}, max(Count) as c, max(Sum) as s FROM otel.otel_metrics_histogram WHERE MetricName = '${metric}' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, h, inst, a, ${alias}) WINDOW w AS (PARTITION BY h, inst, a ORDER BY time ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)"

let histRate =
      \(metric : Text) ->
      \(groupKey : Text) ->
      \(alias : Text) ->
        "SELECT time, ${alias}, sum(dc) / 30 as value FROM (${histDeltas metric groupKey alias}) GROUP BY time, ${alias} ORDER BY time"

let histAvg =
      \(metric : Text) ->
      \(groupKey : Text) ->
      \(alias : Text) ->
        "SELECT time, ${alias}, sum(ds) / sum(dc) as value FROM (${histDeltas metric groupKey alias}) GROUP BY time, ${alias} HAVING sum(dc) > 0 ORDER BY time"

--  The RE service's journal units: nativelink.service on a monolithic host,
--  one unit per process on a split one (nativelink/data/fleet.dhall layout):
--  nativelink-scheduler, nativelink-cas, nativelink-worker-<n>.
let reUnits =
      "match(${S.unit}, '^nativelink(-(scheduler|cas|worker(-[0-9]+)?))?[.]service\$')"

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
            [ P.statLogsWhere "Log lines" reUnits // { width = 6 }
            , P.statErrorsWhere "Errors" reUnits // { width = 6 }
            ,     P.stat
                    "Active nodes"
                    "SELECT uniq(${S.host}) as value FROM ${S.logs} WHERE ${reUnits} AND Timestamp > now() - INTERVAL 1 HOUR"
              //  { width = 6 }
            ,     P.stat
                    "Lines/min"
                    "SELECT count() / 360 as value FROM ${S.logs} WHERE ${reUnits} AND ${S.tfLog}"
              //  { width = 6 }
            ]
          }
        , T.Row::{
          , title = "Remote Execution — Activity"
          , panels =
            [ P.logVolumeWhere "Log volume" reUnits
            , P.timeseries
                "Events by host"
                T.Unit.Short
                "SELECT toStartOfFiveMinutes(Timestamp) as time, ${S.host} as node, count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'nativelink%' AND ${S.tfLog} AND ${S.hostFilter} GROUP BY time, node ORDER BY time"
            ]
          }
        , T.Row::{
          , title = "Remote Execution — Execution"
          , panels =
            [ P.timeseries
                "Actions completed / s"
                T.Unit.OpsPerSec
                (histRate "execution.total.duration" "'all'" "actions")
            , P.timeseries
                "Action time, avg — queue vs total"
                T.Unit.Seconds
                "SELECT time, series, value FROM (${histAvg "execution.queue.time" "'queue'" "series"} UNION ALL ${histAvg "execution.total.duration" "'total'" "series"}) ORDER BY time"
            , P.timeseries
                "Stage time, avg — fetch / execute / upload"
                T.Unit.Seconds
                (histAvg "execution.stage.duration" "Attributes['execution.stage']" "stage")
            , P.timeseries
                "Output size per action, avg"
                T.Unit.Bytes
                (histAvg "execution.output.size" "'output'" "series")
            , P.timeseries
                "Peak memory per action, avg"
                T.Unit.Bytes
                (histAvg "execution.peak.memory" "'peak'" "series")
            ]
          }
        , T.Row::{
          , title = "CAS — Tier Performance"
          , panels =
            [ P.stat
                "Reads served by the fast tier — %"
                "SELECT round(100 * sumIf(d, tier = 'fast' AND res = 'hit') / greatest(sumIf(d, res = 'hit'), 1), 1) as value FROM (SELECT Attributes['store.tier'] as tier, Attributes['store.result'] as res, max(Value) - min(Value) as d FROM ${S.sum} WHERE MetricName = 'store.tier.operations' AND ${S.tf} AND ${S.hostFilter} GROUP BY ${S.host}, ResourceAttributes['service.instance.id'], tier, res)"
            , P.timeseriesStacked
                "Tier ops / s by result"
                T.Unit.OpsPerSec
                ( S.rateBucketed
                    "store.tier.operations"
                    "1"
                    "concat(Attributes['store.tier'], ' ', Attributes['store.result'])"
                    "series"
                )
            , P.timeseries
                "Read throughput by tier"
                T.Unit.BytesPerSec
                ( S.rateBucketed
                    "store.tier.io"
                    "Attributes['store.direction'] = 'read'"
                    "Attributes['store.tier']"
                    "tier"
                )
            , P.timeseries
                "Write throughput by tier"
                T.Unit.BytesPerSec
                ( S.rateBucketed
                    "store.tier.io"
                    "Attributes['store.direction'] = 'write'"
                    "Attributes['store.tier']"
                    "tier"
                )
            , P.timeseries
                "RPC latency, avg by method"
                T.Unit.Seconds
                (histAvg "rpc.server.duration" "Attributes['rpc.method']" "method")
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
