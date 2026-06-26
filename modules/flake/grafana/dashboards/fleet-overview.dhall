--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                              // hypermodern // grafana // fleet overview
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  The battle station. Everything at a glance.

let T = ../schema/types.dhall
let P = ../schema/panels.dhall
let render = ../schema/render.dhall

let hostVariable =
      T.Variable::{
      , name = "host"
      , label = "Host"
      , query =
          ''
          SELECT DISTINCT ResourceAttributes['host.name']
          FROM otel.otel_metrics
          WHERE $__timeFilter(Timestamp)
          ''
      , multi = False
      , includeAll = True
      }

in  render T.Dashboard::{
    , title = "Fleet Overview"
    , uid = "fleet-overview"
    , description = "straylight fleet — all hosts, all signals"
    , tags = [ "fleet", "overview" ]
    , refresh = "30s"
    , timeFrom = "now-1h"
    , variables = [ hostVariable ]
    , rows =
      [ T.Row::{
        , title = "Host Resources"
        , panels = [ P.cpuUsage, P.memoryUsage, P.diskIO ]
        }
      , T.Row::{
        , title = "Network & Load"
        , panels = [ P.networkTraffic, P.loadAverage ]
        }
      , T.Row::{
        , title = "Services"
        , panels = [ P.clickhouseQueries, P.corednsQueries ]
        }
      , T.Row::{
        , title = "Logs"
        , panels = [ P.errorLogs, P.recentLogs ]
        }
      ]
    }
