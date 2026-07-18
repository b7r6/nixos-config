--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // grafana // sql
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  SQL query builder for OTel ClickHouse tables. encodes the patterns that were
--  sources of bugs when written as raw strings:
--    - $__timeFilter macro for metrics vs logs (TimeUnix vs Timestamp)
--    - host IN($host) filter (not string comparison)
--    - runningDifference rate wrapped in subquery + ORDER BY time outer
--    - journald JSON extraction (Body is JSON, not LogAttributes)
--    - 30s scrape interval for rate denominators

-- ── table references ───────────────────────────────────────────────────────────
let gauge = "otel.otel_metrics_gauge"

let sum = "otel.otel_metrics_sum"

let logs = "otel.otel_logs"

let tf = "\$__timeFilter(TimeUnix)"

let tfLog = "\$__timeFilter(Timestamp)"

let host = "ResourceAttributes['host.name']"

let hostFilter = "${host} IN (\$host)"

let hostFilterSingle = "${host} = '\$host'"

let unit = "JSONExtractString(Body, '_SYSTEMD_UNIT')"

let msg = "JSONExtractString(Body, 'MESSAGE')"

let pri = "JSONExtractInt(Body, 'PRIORITY')"

let isErr = "${pri} <= 3"

let isWarn = "${pri} <= 4"

let severityExpr =
      "multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug')"

let rateSimple =
      \(metric : Text) ->
        "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM ${sum} WHERE MetricName = '${metric}' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time"

let rateByKey =
      \(metric : Text) ->
      \(keyExpr : Text) ->
      \(keyAlias : Text) ->
        "SELECT time, ${keyAlias}, value FROM (SELECT TimeUnix as time, ${keyExpr} as ${keyAlias}, runningDifference(Value) / 30 as value FROM ${sum} WHERE MetricName = '${metric}' AND ${tf} ORDER BY ${keyAlias}, time) WHERE value >= 0 ORDER BY time"

let rateBucketed =
      \(metric : Text) ->
      \(extraFilter : Text) ->
      \(groupKeys : Text) ->
      \(groupAliases : Text) ->
        "SELECT time, ${groupAliases}, sum(rate) as value FROM (SELECT time, ${groupAliases}, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${groupKeys}, max(Value) as val FROM ${sum} WHERE MetricName = '${metric}' AND ${extraFilter} AND ${tf} AND ${hostFilter} GROUP BY time, ${groupKeys} ORDER BY ${groupKeys}, time)) WHERE rate >= 0 GROUP BY time, ${groupAliases} ORDER BY time"

let statGauge =
      \(metric : Text) ->
        "SELECT avg(Value) as value FROM ${gauge} WHERE MetricName = '${metric}' AND TimeUnix > now() - INTERVAL 2 MINUTE"

-- Raw scraped nativelink_* metrics land in the GAUGE table (the fork's
-- /metrics renderer emits every value as a gauge, cumulative counters
-- included). gaugeByHost plots a point-in-time gauge per host; rateGaugeByHost
-- differences a cumulative gauge into a per-second rate (runningDifference in a
-- subquery, ORDER BY time outer — same shape as rateBucketed but off `gauge`).
let gaugeByHost =
      \(metric : Text) ->
        "SELECT toStartOfMinute(TimeUnix) as time, ${host} as node, avg(Value) as value FROM ${gauge} WHERE MetricName = '${metric}' AND ${tf} AND ${hostFilter} GROUP BY time, node ORDER BY time"

let rateGaugeByHost =
      \(metric : Text) ->
        "SELECT time, node, sum(rate) as value FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${host} as node, runningDifference(max(Value)) / 30 as rate FROM ${gauge} WHERE MetricName = '${metric}' AND ${tf} AND ${hostFilter} GROUP BY time, node ORDER BY node, time) WHERE rate >= 0 GROUP BY time, node ORDER BY time"

let statLogCount =
      \(unitName : Text) ->
        "SELECT count() as value FROM ${logs} WHERE ${unit} = '${unitName}' AND ${tfLog}"

let statLogErrors =
      \(unitName : Text) ->
        "SELECT count() as value FROM ${logs} WHERE ${unit} = '${unitName}' AND ${isErr} AND ${tfLog}"

let logVolume =
      \(unitName : Text) ->
        "SELECT toStartOfFiveMinutes(Timestamp) as time, ${severityExpr} as severity, count() as value FROM ${logs} WHERE ${unit} = '${unitName}' AND ${tfLog} GROUP BY time, severity ORDER BY time"

let logErrors =
      \(unitName : Text) ->
      \(limit : Natural) ->
        "SELECT Timestamp, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', 'info') as level, substring(${msg}, 1, 400) as message FROM ${logs} WHERE ${unit} = '${unitName}' AND ${isErr} AND ${tfLog} ORDER BY Timestamp DESC LIMIT ${Natural/show
                                                                                                                                                                                                                                              limit}"

in  { gauge
    , sum
    , logs
    , tf
    , tfLog
    , host
    , hostFilter
    , hostFilterSingle
    , unit
    , msg
    , pri
    , isErr
    , isWarn
    , severityExpr
    , rateSimple
    , rateByKey
    , rateBucketed
    , statGauge
    , gaugeByHost
    , rateGaugeByHost
    , statLogCount
    , statLogErrors
    , logVolume
    , logErrors
    }
