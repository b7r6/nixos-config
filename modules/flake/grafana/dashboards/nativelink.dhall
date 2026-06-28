-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                     // hypermodern // grafana // nativelink
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let Q = ../schema/queries.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let hostVar = T.Variable::{ name = "host", label = "Host", type = T.VariableType.Query, query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1", includeAll = True }
let svc = "nativelink.service"

let dashboard =
      T.Dashboard::{
      , title = "NativeLink (Remote Execution)"
      , uid = "nativelink"
      , tags = [ "nativelink", "build" ]
      , refresh = "1m"
      , timeFrom = "now-6h"
      , variables = [ hostVar ]
      , rows =
          [ T.Row::{
            , title = "Health"
            , panels =
                [ (P.statLogs "Log lines" svc) // { width = 6 }
                , (P.statErrors "Errors" svc) // { width = 6 }
                , (P.stat "Active nodes" "SELECT uniq(${S.host}) as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND Timestamp > now() - INTERVAL 1 HOUR") // { width = 6 }
                , (P.stat "Lines/min" "SELECT count() / 360 as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND ${S.tfLog}") // { width = 6 }
                ]
            }
          , T.Row::{
            , title = "Activity"
            , panels =
                [ P.logVolume "Log volume" svc
                , P.timeseries "Events by host" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, ${S.host} as node, count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'nativelink%' AND ${S.tfLog} AND ${S.hostFilter} GROUP BY time, node ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Errors"
            , panels =
                [ P.table "All errors"
                    "SELECT Timestamp, ${S.host} as host, ${S.unit} as unit, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.unit} LIKE 'nativelink%' AND ${S.isErr} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 100"
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
