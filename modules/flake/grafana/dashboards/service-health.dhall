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
      , timeFrom = "now-30m"
      , rows =
        [ T.Row::{
          , title = "Fleet status"
          , panels =
            [     P.statWithThreshold
                    "Hosts UP"
                    "SELECT uniq(${S.host}) as value FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 2 MINUTE"
                    T.thresholdHealth
              //  { width = 6, decimals = Some 0 }
            ,     P.statWithThreshold
                    "Errors (5m)"
                    "SELECT count() as value FROM ${S.logs} WHERE ${S.isErr} AND Timestamp > now() - INTERVAL 5 MINUTE"
                    T.thresholdErrors
              //  { width = 6, decimals = Some 0 }
            ,     P.stat
                    "Metric points / min"
                    "SELECT count() / 5 as value FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 5 MINUTE"
              //  { width = 6, decimals = Some 0 }
            ,     P.stat
                    "Log lines / min"
                    "SELECT count() / 5 as value FROM ${S.logs} WHERE Timestamp > now() - INTERVAL 5 MINUTE"
              //  { width = 6, decimals = Some 0 }
            ]
          }
        , T.Row::{
          , title = "Host liveness"
          , panels =
            [     P.table
                    "Hosts, last seen"
                    "SELECT ${S.host} as host, max(TimeUnix) as \"last seen\", dateDiff('second', max(TimeUnix), now()) as \"seconds ago\", if(dateDiff('second', max(TimeUnix), now()) < 120, 'up', 'down') as status FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 10 MINUTE GROUP BY host ORDER BY \"seconds ago\" ASC"
              //  { height = 5 }
            ]
          }
        , T.Row::{
          , title = "Service errors, by systemd unit"
          , panels =
            [     P.table
                    "Units with errors, last hour"
                    "SELECT ${S.host} as host, ${S.unit} as unit, count() as errors, max(Timestamp) as \"last error\" FROM ${S.logs} WHERE ${S.isErr} AND Timestamp > now() - INTERVAL 1 HOUR AND ${S.unit} != '' GROUP BY host, unit ORDER BY errors DESC LIMIT 30"
              //  { height = 7 }
            ]
          }
        , T.Row::{
          , title = "OTel pipeline"
          , panels =
            [ P.timeseriesSingle
                "Metric points ingested / min"
                T.Unit.Short
                "SELECT toStartOfMinute(TimeUnix) as time, count() as value FROM ${S.gauge} WHERE ${S.tf} GROUP BY time ORDER BY time"
            , P.timeseriesSingle
                "Log lines ingested / min"
                T.Unit.Short
                "SELECT toStartOfMinute(Timestamp) as time, count() as value FROM ${S.logs} WHERE ${S.tfLog} GROUP BY time ORDER BY time"
            ]
          }
        ]
      }

in  R.renderDashboard dashboard
