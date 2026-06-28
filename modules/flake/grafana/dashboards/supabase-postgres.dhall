-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                  // hypermodern // grafana // supabase-postgres
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let Q = ../schema/queries.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let dashboard =
      T.Dashboard::{
      , title = "Supabase / PostgreSQL"
      , uid = "supabase-postgres"
      , tags = [ "supabase", "postgres" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , rows =
          [ T.Row::{
            , title = "Health"
            , panels =
                [ P.statGauge "Pool available" "pgrst_db_pool_available"
                , (P.statWithThreshold "Pool waiting" (Q.statGauge "pgrst_db_pool_waiting") T.thresholdErrors)
                , (P.statWithThreshold "Pool timeouts" "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) as rate FROM ${S.sum} WHERE MetricName = 'pgrst_db_pool_timeouts_total' AND TimeUnix > now() - INTERVAL 5 MINUTE ORDER BY TimeUnix) WHERE rate >= 0" T.thresholdErrors)
                , (P.stat "Schema cache time" (Q.statGauge "pgrst_schema_cache_query_time_seconds")) // { unit = T.Unit.Seconds }
                , P.statErrors "PG17 errors" "supabase-db.service"
                , P.statErrors "Auth errors" "supabase-auth.service"
                ]
            }
          , T.Row::{
            , title = "PostgREST Pool"
            , panels =
                [ (P.timeseries "Available / max" T.Unit.Short (Q.gaugeMulti "'pgrst_db_pool_available', 'pgrst_db_pool_max'")) // { width = 8 }
                , (P.timeseries "Waiting" T.Unit.Short (Q.gaugeForHost "pgrst_db_pool_waiting")) // { width = 8, thresholds = Some T.thresholdErrors }
                , (P.timeseries "Timeouts" T.Unit.Short (Q.rate "pgrst_db_pool_timeouts_total")) // { width = 8, thresholds = Some T.thresholdErrors }
                ]
            }
          , T.Row::{
            , title = "JWT & Schema Cache"
            , panels =
                [ (P.timeseries "JWT hit rate" T.Unit.Percentunit
                    "SELECT TimeUnix as time, if(sum(req.Value) > 0, sum(hit.Value) / sum(req.Value), 1) as value FROM ${S.sum} hit INNER JOIN ${S.sum} req ON hit.TimeUnix = req.TimeUnix WHERE hit.MetricName = 'pgrst_jwt_cache_hits_total' AND req.MetricName = 'pgrst_jwt_cache_requests_total' AND hit.${S.tf} GROUP BY time ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "JWT ops/sec" T.Unit.OpsPerSec
                    (Q.rateByKey "pgrst_jwt_cache_requests_total" "MetricName" "metric")
                  ) // { width = 8 }
                , (P.timeseries "Schema loads" T.Unit.Short
                    "SELECT TimeUnix as time, Attributes['status'] as status, runningDifference(Value) as value FROM ${S.sum} WHERE MetricName = 'pgrst_schema_cache_loads_total' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"
                  ) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "GoTrue / Auth"
            , panels =
                [ P.logVolume "Auth log volume" "supabase-auth.service"
                , (P.timeseriesStacked "Auth events" T.Unit.Short
                    "SELECT toStartOfMinute(Timestamp) as time, multiIf(Body LIKE '%login%' OR Body LIKE '%signin%', 'login', Body LIKE '%signup%' OR Body LIKE '%register%', 'signup', Body LIKE '%token%' OR Body LIKE '%refresh%', 'token', Body LIKE '%oauth%' OR Body LIKE '%oidc%', 'oauth', 'other') as event, count() as value FROM ${S.logs} WHERE ${S.unit} = 'supabase-auth.service' AND ${S.tfLog} AND (Body LIKE '%login%' OR Body LIKE '%signup%' OR Body LIKE '%token%' OR Body LIKE '%oauth%' OR Body LIKE '%signin%' OR Body LIKE '%register%' OR Body LIKE '%refresh%' OR Body LIKE '%oidc%') GROUP BY time, event ORDER BY time"
                  ) // { fillOpacity = 60 }
                ]
            }
          , T.Row::{
            , title = "Storage & Realtime"
            , panels =
                [ (P.logVolume "Storage" "supabase-storage.service") // { width = 8 }
                , (P.logVolume "Realtime" "supabase-realtime.service") // { width = 8 }
                , (P.timeseries "Meta + Studio" T.Unit.Short
                    "SELECT toStartOfMinute(Timestamp) as time, ${S.unit} as svc, count() as value FROM ${S.logs} WHERE ${S.unit} IN ('supabase-meta.service', 'supabase-studio.service') AND ${S.tfLog} GROUP BY time, svc ORDER BY time"
                  ) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "PostgreSQL 17"
            , panels = [ (P.logVolume "PG17 log volume" "supabase-db.service") // { width = 24, height = 6 } ]
            }
          , T.Row::{
            , title = "All Errors"
            , panels =
                [ P.table "Stack errors"
                    "SELECT Timestamp, ${S.unit} as unit, multiIf(${S.pri} <= 3, 'error', ${S.pri} = 4, 'warning', 'info') as level, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.unit} IN ('supabase-db.service', 'supabase-auth.service', 'supabase-rest.service', 'supabase-storage.service', 'supabase-meta.service', 'supabase-realtime.service', 'supabase-studio.service', 'supabase-imgproxy.service') AND ${S.isErr} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 200"
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
