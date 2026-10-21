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

let hostInventory =
      "SELECT DISTINCT ${host} FROM ${gauge} WHERE MetricName = 'system.cpu.load_average.1m' AND TimeUnix > now() - INTERVAL 30 DAY AND ${host} != '' ORDER BY 1"

--  Two log shapes share otel_logs: journald rows (Body is the JSON record:
--  _SYSTEMD_UNIT / MESSAGE / PRIORITY) and OTLP rows from instrumented
--  services (NativeLink: Body is the message, severity in SeverityNumber,
--  no PRIORITY at all). JSONExtractInt on a non-JSON Body is 0, which used
--  to count every NativeLink line as a priority-0 "error" — so each
--  expression falls back to the OTLP field when the journald key is absent.
let unit =
      "if(JSONHas(Body, '_SYSTEMD_UNIT'), JSONExtractString(Body, '_SYSTEMD_UNIT'), ServiceName)"

--  journald hands a MESSAGE that is not valid UTF-8 (or carries ANSI colour,
--  as every tracing-formatted NativeLink line does) as a JSON ARRAY of bytes;
--  JSONExtractString returns '' for it and the raw record shows [32,32,27,91,…].
--  Decode the byte array back into text and strip the escape sequences, so a
--  log panel reads like a log.
let msgRaw =
      "multiIf(JSONType(Body, 'MESSAGE') = 'Array', arrayStringConcat(arrayMap(x -> char(x), JSONExtract(Body, 'MESSAGE', 'Array(UInt8)')), ''), JSONHas(Body, 'MESSAGE'), JSONExtractString(Body, 'MESSAGE'), Body)"

let msg =
      "replaceRegexpAll(${msgRaw}, '\\x1b\\[[0-9;?]*[A-Za-z]', '')"

--  syslog priority: journald's own, or mapped from the OTLP SeverityNumber
--  (ERROR 17+ → 3, WARN 13+ → 4, INFO 9+ → 6, else debug 7).
let pri =
      "if(JSONHas(Body, 'PRIORITY'), JSONExtractInt(Body, 'PRIORITY'), multiIf(SeverityNumber >= 17, 3, SeverityNumber >= 13, 4, SeverityNumber >= 9, 6, 7))"

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
        -- Rate per SERIES (host x process instance x group), then summed. Each
        -- process restart is a new service.instance.id with a counter from 0,
        -- and several processes can emit one metric (nativelink RE + nix
        -- cache): a max() across them then runningDifference() across group
        -- boundaries produced garbage. lagInFrame defaults to the row's own
        -- value (first point = 0) and greatest(0, …) absorbs counter resets.
        "SELECT time, ${groupAliases}, sum(rate) as value FROM (SELECT time, ${groupAliases}, greatest(0, val - lagInFrame(val, 1, val) OVER (PARTITION BY h, inst, ${groupAliases} ORDER BY time ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${host} as h, ResourceAttributes['service.instance.id'] as inst, ${groupKeys} as ${groupAliases}, max(Value) as val FROM ${sum} WHERE MetricName = '${metric}' AND ${extraFilter} AND ${tf} AND ${hostFilter} GROUP BY time, h, inst, ${groupAliases})) GROUP BY time, ${groupAliases} ORDER BY time"

let statGauge =
      \(metric : Text) ->
        "SELECT avg(Value) as value FROM ${gauge} WHERE MetricName = '${metric}' AND TimeUnix > now() - INTERVAL 2 MINUTE"

let gaugeByHost =
      \(metric : Text) ->
        "SELECT toStartOfMinute(TimeUnix) as time, ${host} as node, avg(Value) as value FROM ${gauge} WHERE MetricName = '${metric}' AND ${tf} AND ${hostFilter} GROUP BY time, node ORDER BY time"

let rateGaugeByHost =
      \(metric : Text) ->
        "SELECT time, node, sum(rate) as value FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${host} as node, runningDifference(max(Value)) / 30 as rate FROM ${gauge} WHERE MetricName = '${metric}' AND ${tf} AND ${hostFilter} GROUP BY time, node ORDER BY node, time) WHERE rate >= 0 GROUP BY time, node ORDER BY time"

let rateGaugeByExtract =
      \(likePattern : Text) ->
      \(regex : Text) ->
      \(keyAlias : Text) ->
        "SELECT time, ${keyAlias}, sum(rate) as value FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, extractGroups(MetricName, '${regex}')[1] as ${keyAlias}, runningDifference(max(Value)) / 30 as rate FROM ${gauge} WHERE MetricName LIKE '${likePattern}' AND ${tf} AND ${hostFilter} GROUP BY time, ${keyAlias} ORDER BY ${keyAlias}, time) WHERE rate >= 0 GROUP BY time, ${keyAlias} ORDER BY time"

--  The journal-log queries over a row predicate, for a panel that spans several
--  units (one service run as several, e.g. a split NativeLink). The per-unit
--  forms below are these with `unit = '<name>'`.
let statLogCountWhere =
      \(predicate : Text) ->
        "SELECT count() as value FROM ${logs} WHERE ${predicate} AND ${tfLog}"

let statLogErrorsWhere =
      \(predicate : Text) ->
        "SELECT count() as value FROM ${logs} WHERE ${predicate} AND ${isErr} AND ${tfLog}"

let logVolumeWhere =
      \(predicate : Text) ->
        "SELECT toStartOfFiveMinutes(Timestamp) as time, ${severityExpr} as severity, count() as value FROM ${logs} WHERE ${predicate} AND ${tfLog} GROUP BY time, severity ORDER BY time"

let unitIs = \(unitName : Text) -> "${unit} = '${unitName}'"

let statLogCount = \(unitName : Text) -> statLogCountWhere (unitIs unitName)

let statLogErrors = \(unitName : Text) -> statLogErrorsWhere (unitIs unitName)

let logVolume = \(unitName : Text) -> logVolumeWhere (unitIs unitName)

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
    , hostInventory
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
    , rateGaugeByExtract
    , statLogCount
    , statLogErrors
    , logVolume
    , statLogCountWhere
    , statLogErrorsWhere
    , logVolumeWhere
    , logErrors
    }
