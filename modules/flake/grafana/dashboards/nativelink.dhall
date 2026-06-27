let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let hostVar = T.Variable::{ name = "host", label = "Host", type = T.VariableType.Query, query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1", includeAll = True }

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
                [ (P.stat "Log lines (6h)" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'nativelink.service' AND ${S.tfLog}") // { width = 6 }
                , (P.statWithThreshold "Errors (6h)" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'nativelink.service' AND ${S.isErr} AND ${S.tfLog}" T.thresholdErrors) // { width = 6 }
                , (P.stat "Active nodes" "SELECT uniq(${S.host}) as value FROM ${S.logs} WHERE ${S.unit} = 'nativelink.service' AND Timestamp > now() - INTERVAL 1 HOUR") // { width = 6 }
                , (P.stat "Lines/min (rate)" "SELECT count() / 360 as value FROM ${S.logs} WHERE ${S.unit} = 'nativelink.service' AND ${S.tfLog}") // { width = 6 }
                ]
            }
          , T.Row::{
            , title = "Scheduler"
            , panels =
                [ P.logVolume "Scheduler log volume" "nativelink.service"
                , P.timeseries "Scheduler connection events" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%connect%', 'connect', Body LIKE '%disconnect%' OR Body LIKE '%drop%', 'disconnect', Body LIKE '%queue%' OR Body LIKE '%schedule%', 'schedule', 'other') as event, count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'nativelink%' AND (Body LIKE '%connect%' OR Body LIKE '%disconnect%' OR Body LIKE '%queue%' OR Body LIKE '%schedule%' OR Body LIKE '%drop%') AND ${S.tfLog} GROUP BY time, event ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Workers"
            , panels =
                [ P.timeseries "Worker log volume by host" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, ${S.host} as node, count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'nativelink%' AND ${S.tfLog} AND ${S.hostFilter} GROUP BY time, node ORDER BY time"
                , (P.timeseriesStacked "Worker execution events" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%execute%' OR Body LIKE '%running%', 'executing', Body LIKE '%complete%' OR Body LIKE '%finish%', 'completed', Body LIKE '%error%' OR Body LIKE '%fail%', 'failed', 'other') as status, count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'nativelink%' AND (Body LIKE '%execute%' OR Body LIKE '%running%' OR Body LIKE '%complete%' OR Body LIKE '%finish%' OR Body LIKE '%error%' OR Body LIKE '%fail%') AND ${S.tfLog} GROUP BY time, status ORDER BY time"
                  ) // { fillOpacity = 60 }
                ]
            }
          , T.Row::{
            , title = "Errors"
            , panels =
                [ P.table "All NativeLink errors"
                    "SELECT Timestamp, ${S.host} as host, ${S.unit} as unit, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.unit} LIKE 'nativelink%' AND ${S.isErr} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 100"
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
