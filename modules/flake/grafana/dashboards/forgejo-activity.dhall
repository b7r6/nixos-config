let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let dashboard =
      T.Dashboard::{
      , title = "Forgejo (Git Forge)"
      , uid = "forgejo-activity"
      , tags = [ "forgejo", "git" ]
      , refresh = "1m"
      , timeFrom = "now-6h"
      , rows =
          [ T.Row::{
            , title = "Health"
            , panels =
                [ P.statGauge "Goroutines" "go_goroutines"
                , (P.stat "Heap alloc" (S.statGauge "go_memstats_heap_alloc_bytes")) // { unit = T.Unit.Bytes }
                , P.statErrors "Errors (6h)" "forgejo.service"
                , (P.stat "Git pushes (6h)" "SELECT count() as value FROM ${S.logs} WHERE Body LIKE '%git-receive-pack%' AND ${S.tfLog}")
                , (P.stat "Git fetches (6h)" "SELECT count() as value FROM ${S.logs} WHERE Body LIKE '%git-upload-pack%' AND ${S.tfLog}")
                , (P.stat "HTTP requests/min" "SELECT sum(rate) / 60 as value FROM (SELECT runningDifference(Value) as rate FROM ${S.sum} WHERE MetricName = 'process_open_fds' AND ${S.host} = 'watchtower' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0")
                ]
            }
          , T.Row::{
            , title = "Go Runtime"
            , panels =
                [ (P.timeseries "Goroutines" T.Unit.Short
                    "SELECT TimeUnix as time, avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'go_goroutines' AND ${S.host} = 'watchtower' AND ${S.tf} GROUP BY time ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Heap memory (alloc / sys)" T.Unit.Bytes
                    "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM ${S.gauge} WHERE MetricName IN ('go_memstats_heap_alloc_bytes', 'go_memstats_heap_sys_bytes') AND ${S.host} = 'watchtower' AND ${S.tf} GROUP BY time, metric ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Process CPU seconds/interval" T.Unit.Seconds
                    "SELECT TimeUnix as time, runningDifference(Value) as value FROM ${S.sum} WHERE MetricName = 'process_cpu_seconds_total' AND ${S.host} = 'watchtower' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"
                  ) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Git Operations"
            , panels =
                [ (P.timeseriesStacked "Git push/fetch rate" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%git-receive-pack%', 'push', Body LIKE '%git-upload-pack%', 'fetch', 'other') as op, count() as value FROM ${S.logs} WHERE (Body LIKE '%git-receive-pack%' OR Body LIKE '%git-upload-pack%') AND ${S.tfLog} GROUP BY time, op ORDER BY time"
                  ) // { fillOpacity = 60 }
                , P.timeseries "SSH vs HTTP git traffic" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%SSH%' OR Body LIKE '%ssh%', 'ssh', Body LIKE '%HTTP%' OR Body LIKE '%http%', 'http', 'unknown') as proto, count() as value FROM ${S.logs} WHERE ${S.unit} = 'forgejo.service' AND (Body LIKE '%git-%pack%' OR Body LIKE '%refs/%') AND ${S.tfLog} GROUP BY time, proto ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Logs"
            , panels =
                [ (P.logVolume "Forgejo log volume by severity" "forgejo.service") // { width = 24, height = 6 }
                ]
            }
          , T.Row::{
            , title = "Errors & Activity"
            , panels =
                [ (P.errorTable "Forgejo errors" "forgejo.service") // { height = 8 }
                , (P.table "Recent git activity"
                    "SELECT Timestamp, substring(${S.msg}, 1, 400) as activity FROM ${S.logs} WHERE (Body LIKE '%git-receive-pack%' OR Body LIKE '%git-upload-pack%' OR Body LIKE '%refs/heads%') AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 50"
                  ) // { height = 8 }
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
