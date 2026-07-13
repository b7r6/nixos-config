-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                       // hypermodern // grafana // attic
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
let T = ../schema/types.dhall

let S = ../schema/sql.dhall

let P = ../schema/panels.dhall

let R = ../schema/render.dhall

let hostVar =
      T.Variable::{
      , name = "host"
      , label = "Host"
      , type = T.VariableType.Query
      , query =
          "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1"
      , includeAll = True
      }

let svc = "atticd.service"

let dashboard =
      T.Dashboard::{
      , title = "Attic (Binary Cache)"
      , uid = "attic"
      , tags = [ "attic", "nix" ]
      , refresh = "1m"
      , timeFrom = "now-6h"
      , variables = [ hostVar ]
      , rows =
        [ T.Row::{
          , title = "Health"
          , panels =
            [ P.statLogs "Logs (6h)" svc
            , P.statErrors "Errors" svc
            , P.stat
                "Uploads"
                "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND (Body LIKE '%upload%' OR Body LIKE '%PUT%' OR Body LIKE '%push%') AND ${S.tfLog}"
            , P.stat
                "Downloads"
                "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND (Body LIKE '%GET%' OR Body LIKE '%serve%' OR Body LIKE '%download%') AND ${S.tfLog}"
            , P.stat
                "Nodes"
                "SELECT uniq(${S.host}) as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND Timestamp > now() - INTERVAL 1 HOUR"
            , P.stat
                "404s"
                "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND (Body LIKE '%404%' OR Body LIKE '%not found%') AND ${S.tfLog}"
            ]
          }
        , T.Row::{
          , title = "Traffic"
          , panels =
            [ P.timeseries
                "By node"
                T.Unit.Short
                "SELECT toStartOfFiveMinutes(Timestamp) as time, ${S.host} as node, count() as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND ${S.tfLog} AND ${S.hostFilter} GROUP BY time, node ORDER BY time"
            ,     P.timeseriesStacked
                    "Operations"
                    T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%upload%' OR Body LIKE '%PUT%' OR Body LIKE '%push%', 'upload', Body LIKE '%GET%nar%' OR Body LIKE '%serve%' OR Body LIKE '%download%', 'download', Body LIKE '%narinfo%' OR Body LIKE '%HEAD%', 'narinfo', 'other') as op, count() as value FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND (Body LIKE '%upload%' OR Body LIKE '%PUT%' OR Body LIKE '%GET%' OR Body LIKE '%HEAD%' OR Body LIKE '%serve%' OR Body LIKE '%push%' OR Body LIKE '%download%' OR Body LIKE '%narinfo%') AND ${S.tfLog} GROUP BY time, op ORDER BY time"
              //  { fillOpacity = 60 }
            ]
          }
        , T.Row::{ title = "Logs", panels = [ P.logVolume "Volume" svc ] }
        , T.Row::{
          , title = "Errors"
          , panels =
            [ P.table
                "Errors"
                "SELECT Timestamp, ${S.host} as host, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.unit} = '${svc}' AND ${S.isErr} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 100"
            ]
          }
        ]
      }

in  R.renderDashboard dashboard
