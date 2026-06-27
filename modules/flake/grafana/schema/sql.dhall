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

-- ── time filters ───────────────────────────────────────────────────────────────

let tf = "\$__timeFilter(TimeUnix)"
let tfLog = "\$__timeFilter(Timestamp)"

-- ── host column ────────────────────────────────────────────────────────────────

let host = "ResourceAttributes['host.name']"

-- ── host filter: uses IN($host) which grafana expands to all selected values ──

let hostFilter = "${host} IN (\$host)"

-- single-host filter (for drilldown dashboards with includeAll=false)
let hostFilterSingle = "${host} = '\$host'"

-- ── journald log helpers ───────────────────────────────────────────────────────
-- journald logs arrive as JSON in Body. LogAttributes and SeverityText are empty.
-- PRIORITY: 0=emerg, 1=alert, 2=crit, 3=err, 4=warn, 5=notice, 6=info, 7=debug

let unit = "JSONExtractString(Body, '_SYSTEMD_UNIT')"
let msg = "JSONExtractString(Body, 'MESSAGE')"
let pri = "JSONExtractInt(Body, 'PRIORITY')"
let isErr = "${pri} <= 3"
let isWarn = "${pri} <= 4"

-- severity classification for display
let severityExpr =
      "multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', ${pri} = 5, 'notice', ${pri} = 6, 'info', 'debug')"

-- ── rate helper ────────────────────────────────────────────────────────────────
-- for OTel cumulative counters. wraps in subquery so:
--   1. inner query orders by series key (for correct runningDifference)
--   2. outer query filters negative deltas and orders by time (for grafana plugin)
--
-- usage: rate "MetricName" "series_col" "series_alias"
-- produces a query that returns (time, series_alias, value) ordered by time

let rateSimple =
      \(metric : Text) ->
        "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM ${sum} WHERE MetricName = '${metric}' AND ${tf} AND runningDifference(Value) >= 0 ORDER BY time"

-- rate with a series split column (e.g. MetricName, host, etc.)
-- the key pattern: subquery ORDER BY series,time → outer ORDER BY time
let rateByKey =
      \(metric : Text) ->
      \(keyExpr : Text) ->
      \(keyAlias : Text) ->
        "SELECT time, ${keyAlias}, value FROM (SELECT TimeUnix as time, ${keyExpr} as ${keyAlias}, runningDifference(Value) / 30 as value FROM ${sum} WHERE MetricName = '${metric}' AND ${tf} ORDER BY ${keyAlias}, time) WHERE value >= 0 ORDER BY time"

-- rate for multi-device metrics (disk.io, network.io) that need bucketing
-- groups by 30s intervals, takes max per device, then computes rate
let rateBucketed =
      \(metric : Text) ->
      \(extraFilter : Text) ->
      \(groupKeys : Text) ->
      \(groupAliases : Text) ->
        "SELECT time, ${groupAliases}, sum(rate) as value FROM (SELECT time, ${groupAliases}, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${groupKeys}, max(Value) as val FROM ${sum} WHERE MetricName = '${metric}' AND ${extraFilter} AND ${tf} AND ${hostFilter} GROUP BY time, ${groupKeys} ORDER BY ${groupKeys}, time)) WHERE rate >= 0 GROUP BY time, ${groupAliases} ORDER BY time"

-- ── common stat queries ────────────────────────────────────────────────────────

let statGauge =
      \(metric : Text) ->
        "SELECT avg(Value) as value FROM ${gauge} WHERE MetricName = '${metric}' AND TimeUnix > now() - INTERVAL 2 MINUTE"

let statLogCount =
      \(unitName : Text) ->
        "SELECT count() as value FROM ${logs} WHERE ${unit} = '${unitName}' AND ${tfLog}"

let statLogErrors =
      \(unitName : Text) ->
        "SELECT count() as value FROM ${logs} WHERE ${unit} = '${unitName}' AND ${isErr} AND ${tfLog}"

-- ── log volume query (severity stacked) ────────────────────────────────────────

let logVolume =
      \(unitName : Text) ->
        "SELECT toStartOfFiveMinutes(Timestamp) as time, ${severityExpr} as severity, count() as value FROM ${logs} WHERE ${unit} = '${unitName}' AND ${tfLog} GROUP BY time, severity ORDER BY time"

-- ── log error table ────────────────────────────────────────────────────────────

let logErrors =
      \(unitName : Text) ->
      \(limit : Natural) ->
        "SELECT Timestamp, multiIf(${pri} <= 3, 'error', ${pri} = 4, 'warning', 'info') as level, substring(${msg}, 1, 400) as message FROM ${logs} WHERE ${unit} = '${unitName}' AND ${isErr} AND ${tfLog} ORDER BY Timestamp DESC LIMIT ${Natural/show limit}"

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
    , statLogCount
    , statLogErrors
    , logVolume
    , logErrors
    }
