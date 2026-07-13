-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                             // hypermodern // grafana // queries
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- composable query combinators for OTel ClickHouse tables.
-- each encodes a pattern that was a source of bugs when hand-written:
--   - correct ORDER BY (series key inner, time outer)
--   - bucketed max for multi-datapoint-per-scrape metrics
--   - runningDifference only where appropriate (counters, not gauges)
--   - proper aggregate (avg for gauges, sum for counters, max for snapshots)
let S = ./sql.dhall

let gaugeByHost =
      \(metric : Text) ->
        "SELECT TimeUnix as time, ${S.host} as host, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host ORDER BY time"

let gaugeByLabel =
      \(metric : Text) ->
      \(labelExpr : Text) ->
      \(alias : Text) ->
        "SELECT TimeUnix as time, ${labelExpr} as ${alias}, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${S.tf} GROUP BY time, ${alias} ORDER BY time"

let gaugeMulti =
      \(metrics : Text) ->
        "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM ${S.gauge} WHERE MetricName IN (${metrics}) AND ${S.tf} GROUP BY time, metric ORDER BY time"

let gaugeForHost =
      \(metric : Text) ->
        "SELECT TimeUnix as time, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time ORDER BY time"

let gaugeSingle =
      \(metric : Text) ->
        "SELECT TimeUnix as time, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${S.tf} GROUP BY time ORDER BY time"

let statGauge =
      \(metric : Text) ->
        "SELECT avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND TimeUnix > now() - INTERVAL 2 MINUTE"

let rate =
      \(metric : Text) ->
        "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM ${S.sum} WHERE MetricName = '${metric}' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"

let rateByKey =
      \(metric : Text) ->
      \(keyExpr : Text) ->
      \(alias : Text) ->
        "SELECT time, ${alias}, value FROM (SELECT TimeUnix as time, ${keyExpr} as ${alias}, runningDifference(Value) / 30 as value FROM ${S.sum} WHERE MetricName = '${metric}' AND ${S.tf} ORDER BY ${alias}, time) WHERE value >= 0 ORDER BY time"

let rateByHost = \(metric : Text) -> rateByKey metric S.host "host"

let rateByAttr =
      \(metric : Text) ->
      \(attr : Text) ->
      \(alias : Text) ->
        rateByKey metric "Attributes['${attr}']" alias

let rateBucketed =
      \(metric : Text) ->
      \(filter : Text) ->
      \(innerKeys : Text) ->
      \(outerKeys : Text) ->
        "SELECT time, ${outerKeys}, sum(rate) as value FROM (SELECT time, ${outerKeys}, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${innerKeys}, max(Value) as val FROM ${S.sum} WHERE MetricName = '${metric}' AND ${filter} AND ${S.tf} AND ${S.hostFilter} GROUP BY time, ${innerKeys} ORDER BY ${innerKeys}, time)) WHERE rate >= 0 GROUP BY time, ${outerKeys} ORDER BY time"

let rateBucketedForHost =
      \(metric : Text) ->
      \(filter : Text) ->
      \(keys : Text) ->
      \(aliases : Text) ->
        "SELECT time, ${aliases}, value FROM (SELECT time, ${aliases}, runningDifference(val) / 30 as value FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${keys}, max(Value) as val FROM ${S.sum} WHERE MetricName = '${metric}' AND ${filter} AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time, ${keys} ORDER BY ${keys}, time)) WHERE value >= 0 ORDER BY time"

let sumByHost =
      \(metric : Text) ->
      \(filter : Text) ->
        "SELECT TimeUnix as time, ${S.host} as host, avg(Value) as value FROM ${S.sum} WHERE MetricName = '${metric}' AND ${filter} AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host ORDER BY time"

let sumByAttrForHost =
      \(metric : Text) ->
      \(attr : Text) ->
      \(alias : Text) ->
      \(filter : Text) ->
        "SELECT TimeUnix as time, Attributes['${attr}'] as ${alias}, avg(Value) as value FROM ${S.sum} WHERE MetricName = '${metric}' AND ${filter} AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time, ${alias} ORDER BY time"

let spread =
      \(metric : Text) ->
      \(nodeFilter : Text) ->
        "SELECT TimeUnix as time, max(Value) - min(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${nodeFilter} AND ${S.tf} GROUP BY time ORDER BY time"

let byNodeFiltered =
      \(metric : Text) ->
      \(nodeFilter : Text) ->
      \(alias : Text) ->
        "SELECT TimeUnix as time, ${S.host} as ${alias}, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${nodeFilter} AND ${S.tf} GROUP BY time, ${alias} ORDER BY time"

let statFiltered =
      \(metric : Text) ->
      \(nodeFilter : Text) ->
      \(agg : Text) ->
        "SELECT ${agg}(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${nodeFilter} AND TimeUnix > now() - INTERVAL 2 MINUTE"

let logVolume =
      \(unitName : Text) ->
        "SELECT toStartOfFiveMinutes(Timestamp) as time, ${S.severityExpr} as severity, count() as value FROM ${S.logs} WHERE ${S.unit} = '${unitName}' AND ${S.tfLog} GROUP BY time, severity ORDER BY time"

let logErrors =
      \(unitName : Text) ->
      \(limit : Natural) ->
        "SELECT Timestamp, multiIf(${S.pri} <= 3, 'error', ${S.pri} = 4, 'warning', 'info') as level, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.unit} = '${unitName}' AND ${S.isErr} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT ${Natural/show
                                                                                                                                                                                                                                                            limit}"

let statLogs =
      \(unitName : Text) ->
        "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = '${unitName}' AND ${S.tfLog}"

let statErrors =
      \(unitName : Text) ->
        "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = '${unitName}' AND ${S.isErr} AND ${S.tfLog}"

in  { -- gauges
      gaugeByHost
    , gaugeByLabel
    , gaugeMulti
    , gaugeForHost
    , gaugeSingle
    , statGauge
      -- rates (counters)
    , rate
    , rateByKey
    , rateByHost
    , rateByAttr
    , rateBucketed
    , rateBucketedForHost
      -- sums (gauge-like)
    , sumByHost
    , sumByAttrForHost
      -- cross-node
    , spread
    , byNodeFiltered
    , statFiltered
      -- logs
    , logVolume
    , logErrors
    , statLogs
    , statErrors
    }
