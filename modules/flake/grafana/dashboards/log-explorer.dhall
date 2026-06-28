-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                     // hypermodern // grafana // log-explorer
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let Q = ../schema/queries.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let hostVar = T.Variable::{ name = "host", label = "Host", type = T.VariableType.Query, query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1", includeAll = True }
let unitVar = T.Variable::{ name = "unit", label = "Unit", type = T.VariableType.Query, query = "SELECT DISTINCT ${S.unit} FROM ${S.logs} WHERE Timestamp > now() - INTERVAL 1 HOUR AND ${S.unit} != '' ORDER BY 1", includeAll = True }
let searchVar = T.Variable::{ name = "search", label = "Search", type = T.VariableType.Textbox }

let dashboard =
      T.Dashboard::{
      , title = "Log Explorer"
      , uid = "log-explorer"
      , tags = [ "logs" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , variables = [ hostVar, unitVar, searchVar ]
      , rows =
          [ T.Row::{
            , title = "Volume"
            , panels =
                [ (P.timeseriesStacked "Log volume by severity" T.Unit.Short
                    "SELECT toStartOfMinute(Timestamp) as time, ${S.severityExpr} as severity, count() as value FROM ${S.logs} WHERE ${S.tfLog} AND ${S.hostFilter} AND (${S.unit} IN (\$unit) OR ${S.unit} = '') GROUP BY time, severity ORDER BY time"
                  ) // { width = 24, height = 6 }
                ]
            }
          , T.Row::{
            , title = "Errors"
            , panels =
                [ (P.barGauge "Error count by host"
                    "SELECT ${S.host} as host, count() as errors FROM ${S.logs} WHERE ${S.isErr} AND ${S.tfLog} GROUP BY host ORDER BY errors DESC"
                  )
                , (P.barGauge "Error count by unit"
                    "SELECT ${S.unit} as unit, count() as errors FROM ${S.logs} WHERE ${S.isErr} AND ${S.unit} != '' AND ${S.tfLog} GROUP BY unit ORDER BY errors DESC LIMIT 15"
                  )
                , (P.table "Top error messages"
                    "SELECT substring(${S.msg}, 1, 120) as message, count() as n FROM ${S.logs} WHERE ${S.isErr} AND ${S.tfLog} GROUP BY message ORDER BY n DESC LIMIT 20"
                  ) // { width = 8, height = 7 }
                ]
            }
          , T.Row::{
            , title = "Stream"
            , panels =
                [ (P.table "Log stream"
                    "SELECT Timestamp, ${S.host} as host, multiIf(${S.pri} <= 3, 'error', ${S.pri} = 4, 'warning', 'info') as level, ${S.unit} as unit, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.tfLog} AND ${S.hostFilter} AND (${S.unit} IN (\$unit) OR ${S.unit} = '') AND ('\$search' = '' OR Body LIKE '%\$search%') ORDER BY Timestamp DESC LIMIT 500"
                  ) // { height = 14 }
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
