-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                    // hypermodern // grafana // service-health
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
let T = ../schema/types.dhall

let S = ../schema/sql.dhall

let P = ../schema/panels.dhall

let R = ../schema/render.dhall

let dashboard =
      T.Dashboard::{
      , title = "Service Health"
      , uid = "service-health"
      , tags = [ "fleet", "health" ]
      , refresh = "30s"
      , timeFrom = "now-5m"
      , rows =
        [ T.Row::{
          , title = "Fleet Status"
          , panels =
            [     P.statWithThreshold
                    "Hosts UP"
                    "SELECT uniq(${S.host}) as value FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 2 MINUTE"
                    T.thresholdHealth
              //  { width = 6, height = 5 }
            ,     P.statWithThreshold
                    "Errors (5m)"
                    "SELECT count() as value FROM ${S.logs} WHERE ${S.isErr} AND Timestamp > now() - INTERVAL 5 MINUTE"
                    T.thresholdErrors
              //  { width = 6, height = 5 }
            ,     P.stat
                    "Data points/min"
                    "SELECT count() / 5 as value FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 5 MINUTE"
              //  { width = 6, height = 5 }
            ,     P.stat
                    "Log lines/min"
                    "SELECT count() / 5 as value FROM ${S.logs} WHERE Timestamp > now() - INTERVAL 5 MINUTE"
              //  { width = 6, height = 5 }
            ]
          }
        , T.Row::{
          , title = "Host Liveness"
          , panels =
            [     P.table
                    "Host last-seen"
                    "SELECT ${S.host} as host, max(TimeUnix) as last_seen, dateDiff('second', max(TimeUnix), now()) as seconds_ago, if(dateDiff('second', max(TimeUnix), now()) < 120, 'UP', 'DOWN') as status FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 10 MINUTE GROUP BY host ORDER BY seconds_ago ASC"
              //  { height = 7 }
            ]
          }
        , T.Row::{
          , title = "Service Errors (by systemd unit)"
          , panels =
            [     P.table
                    "Top erroring units (last hour)"
                    "SELECT ${S.host} as host, ${S.unit} as unit, count() as errors, max(Timestamp) as last_error FROM ${S.logs} WHERE ${S.isErr} AND Timestamp > now() - INTERVAL 1 HOUR AND ${S.unit} != '' GROUP BY host, unit ORDER BY errors DESC LIMIT 30"
              //  { height = 9 }
            ]
          }
        , T.Row::{
          , title = "OTel Pipeline Health"
          , panels =
            [ P.timeseries
                "Metric ingestion rate"
                T.Unit.Short
                "SELECT toStartOfMinute(TimeUnix) as time, count() as value FROM ${S.gauge} WHERE ${S.tf} GROUP BY time ORDER BY time"
            , P.timeseries
                "Log ingestion rate"
                T.Unit.Short
                "SELECT toStartOfMinute(Timestamp) as time, count() as value FROM ${S.logs} WHERE ${S.tfLog} GROUP BY time ORDER BY time"
            ]
          }
        ]
      }

in  R.renderDashboard dashboard
