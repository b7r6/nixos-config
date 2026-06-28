-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                    // hypermodern // grafana // fleet-overview
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- the battle station. one glance tells you if the fleet is healthy.

let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let Q = ../schema/queries.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

-- ── variables ──────────────────────────────────────────────────────────────────

let hostVar =
      T.Variable::{
      , name = "host"
      , label = "Host"
      , type = T.VariableType.Query
      , query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1"
      , includeAll = True
      }

-- ── dashboard ──────────────────────────────────────────────────────────────────

let dashboard =
      T.Dashboard::{
      , title = "Fleet Overview"
      , uid = "fleet-overview"
      , tags = [ "fleet", "overview" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , variables = [ hostVar ]
      , rows =

          [ -- ── health at a glance ─────────────────────────────────────────────
            T.Row::{
            , title = "Health"
            , panels =
                [ (P.statWithThreshold "Hosts reporting"
                    "SELECT uniq(${S.host}) as value FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 2 MINUTE"
                    T.thresholdHealth
                  ) // { width = 4 }

                , (P.statWithThreshold "Fleet load avg"
                    (Q.statGauge "system.cpu.load_average.1m")
                    T.thresholdLoad
                  ) // { width = 4 }

                , (P.statWithThreshold "Fleet memory %"
                    "SELECT sum(case when Attributes['state'] = 'used' then Value else 0 end) / sum(Value) as value FROM ${S.sum} WHERE MetricName = 'system.memory.usage' AND TimeUnix > now() - INTERVAL 2 MINUTE AND TimeUnix = (SELECT max(TimeUnix) FROM ${S.sum} WHERE MetricName = 'system.memory.usage' AND TimeUnix > now() - INTERVAL 2 MINUTE)"
                    T.thresholdPct
                  ) // { width = 4 }

                , (P.statWithThreshold "Errors (5m)"
                    "SELECT count() as value FROM ${S.logs} WHERE ${S.isErr} AND Timestamp > now() - INTERVAL 5 MINUTE"
                    T.thresholdErrors
                  ) // { width = 4 }

                , (P.stat "OTel points/min"
                    "SELECT count() / 5 as value FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 5 MINUTE"
                  ) // { width = 4 }

                , (P.stat "DNS queries/s"
                    "SELECT avg(rate) as value FROM (SELECT ${S.host} as h, runningDifference(Value) / 30 as rate FROM ${S.sum} WHERE MetricName = 'coredns_dns_requests_total' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0"
                  ) // { width = 4, unit = T.Unit.ReqPerSec }
                ]
            }

          , -- ── compute ────────────────────────────────────────────────────────
            T.Row::{
            , title = "Compute"
            , panels =
                [ (P.timeseries "Load average (1m) by host" T.Unit.Short
                    (Q.gaugeByHost "system.cpu.load_average.1m")
                  ) // { width = 8, height = 7, thresholds = Some T.thresholdLoad }

                , (P.timeseries "Memory used by host" T.Unit.Bytes
                    (Q.sumByHost "system.memory.usage" "Attributes['state'] = 'used'")
                  ) // { width = 8, height = 7 }

                , (P.timeseries "Paging ops/sec by host" T.Unit.OpsPerSec
                    (Q.rateBucketed "system.paging.operations" "1=1"
                      "${S.host} as host, Attributes['direction'] as dir"
                      "host, dir")
                  ) // { width = 8, height = 7
                     , description = "page in/out. high = memory pressure."
                     }
                ]
            }

          , -- ── storage ────────────────────────────────────────────────────────
            T.Row::{
            , title = "Storage"
            , panels =
                [ (P.timeseries "Disk I/O rate by host" T.Unit.BytesPerSec
                    (Q.rateBucketed "system.disk.io" "1=1"
                      "${S.host} as host, Attributes['direction'] as dir, Attributes['device'] as dev"
                      "host, dir")
                  ) // { height = 7 }

                , (P.timeseries "Filesystem used % by host" T.Unit.Percentunit
                    "SELECT TimeUnix as time, ${S.host} as host, Attributes['mountpoint'] as mount, sumIf(Value, Attributes['state'] = 'used') / sum(Value) as value FROM ${S.sum} WHERE MetricName = 'system.filesystem.usage' AND Attributes['mountpoint'] NOT LIKE '/nix%' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host, mount HAVING sum(Value) > 0 ORDER BY time"
                  ) // { height = 7, thresholds = Some T.thresholdPct }
                ]
            }

          , -- ── network ────────────────────────────────────────────────────────
            T.Row::{
            , title = "Network"
            , panels =
                [ (P.timeseries "Network throughput by host" T.Unit.BytesPerSec
                    (Q.rateBucketed "system.network.io" "Attributes['device'] != 'lo'"
                      "${S.host} as host, Attributes['direction'] as dir, Attributes['device'] as dev"
                      "host, dir")
                  ) // { height = 7 }

                , (P.timeseries "Network errors + drops" T.Unit.Short
                    (Q.rateBucketed "system.network.errors" "1=1"
                      "${S.host} as host, Attributes['device'] as dev"
                      "host")
                  ) // { height = 7, thresholds = Some T.thresholdErrors }
                ]
            }

          , -- ── services ───────────────────────────────────────────────────────
            T.Row::{
            , title = "Services"
            , panels =
                [ (P.timeseries "CoreDNS queries/sec" T.Unit.ReqPerSec
                    (Q.rateByHost "coredns_dns_requests_total")
                  ) // { width = 8, height = 7 }

                , (P.timeseries "DNS cache hit rate" T.Unit.Percentunit
                    "SELECT h.TimeUnix as time, h.${S.host} as host, sum(h.Value) / (sum(h.Value) + sum(m.Value)) as value FROM ${S.sum} h INNER JOIN ${S.sum} m ON h.TimeUnix = m.TimeUnix AND h.${S.host} = m.${S.host} WHERE h.MetricName = 'coredns_cache_hits_total' AND m.MetricName = 'coredns_cache_misses_total' AND h.${S.tf} GROUP BY time, host ORDER BY time"
                  ) // { width = 8, height = 7 }

                , (P.timeseries "PostgREST JWT cache" T.Unit.OpsPerSec
                    (Q.rateByKey "pgrst_jwt_cache_requests_total" "MetricName" "metric")
                  ) // { width = 8, height = 7 }
                ]
            }

          , -- ── errors ─────────────────────────────────────────────────────────
            T.Row::{
            , title = "Recent Errors"
            , panels =
                [ P.table "Error log (last hour)"
                    "SELECT Timestamp, ${S.host} as host, multiIf(${S.pri} <= 3, 'error', ${S.pri} = 4, 'warning', 'info') as level, ${S.unit} as unit, substring(${S.msg}, 1, 300) as message FROM ${S.logs} WHERE ${S.isErr} AND ${S.tfLog} AND ${S.hostFilter} ORDER BY Timestamp DESC LIMIT 200"
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
