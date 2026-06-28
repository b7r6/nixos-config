-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                   // hypermodern // grafana // forgejo-activity
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let Q = ../schema/queries.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

-- go runtime metrics are scraped from forgejo's :3200/metrics on watchtower
let goGauge = \(metric : Text) -> Q.gaugeForHost metric

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
                , (P.stat "Heap alloc" (Q.statGauge "go_memstats_heap_alloc_bytes")) // { unit = T.Unit.Bytes }
                , P.statErrors "Errors (6h)" "forgejo.service"
                , (P.stat "Git pushes" "SELECT count() as value FROM ${S.logs} WHERE Body LIKE '%git-receive-pack%' AND ${S.tfLog}")
                , (P.stat "Git fetches" "SELECT count() as value FROM ${S.logs} WHERE Body LIKE '%git-upload-pack%' AND ${S.tfLog}")
                , (P.stat "Process CPU" "SELECT runningDifference(max(Value)) as value FROM ${S.sum} WHERE MetricName = 'process_cpu_seconds_total' AND ${S.host} = 'watchtower' AND TimeUnix > now() - INTERVAL 2 MINUTE") // { unit = T.Unit.Seconds }
                ]
            }
          , T.Row::{
            , title = "Go Runtime"
            , panels =
                [ (P.timeseries "Goroutines" T.Unit.Short (goGauge "go_goroutines")) // { width = 8 }
                , (P.timeseries "Heap (alloc / sys)" T.Unit.Bytes (Q.gaugeMulti "'go_memstats_heap_alloc_bytes', 'go_memstats_heap_sys_bytes'")) // { width = 8 }
                , (P.timeseries "Process CPU/interval" T.Unit.Seconds (Q.rate "process_cpu_seconds_total")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Git Operations"
            , panels =
                [ (P.timeseriesStacked "Push/fetch rate" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%git-receive-pack%', 'push', Body LIKE '%git-upload-pack%', 'fetch', 'other') as op, count() as value FROM ${S.logs} WHERE (Body LIKE '%git-receive-pack%' OR Body LIKE '%git-upload-pack%') AND ${S.tfLog} GROUP BY time, op ORDER BY time"
                  ) // { fillOpacity = 60 }
                , P.timeseries "SSH vs HTTP" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%SSH%' OR Body LIKE '%ssh%', 'ssh', Body LIKE '%HTTP%' OR Body LIKE '%http%', 'http', 'unknown') as proto, count() as value FROM ${S.logs} WHERE ${S.unit} = 'forgejo.service' AND (Body LIKE '%git-%pack%' OR Body LIKE '%refs/%') AND ${S.tfLog} GROUP BY time, proto ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Logs"
            , panels = [ (P.logVolume "Log volume" "forgejo.service") // { width = 24, height = 6 } ]
            }
          , T.Row::{
            , title = "Errors & Activity"
            , panels =
                [ (P.errorTable "Errors" "forgejo.service") // { height = 8 }
                , (P.table "Recent git activity"
                    "SELECT Timestamp, substring(${S.msg}, 1, 400) as activity FROM ${S.logs} WHERE (Body LIKE '%git-receive-pack%' OR Body LIKE '%git-upload-pack%' OR Body LIKE '%refs/heads%') AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 50"
                  ) // { height = 8 }
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
