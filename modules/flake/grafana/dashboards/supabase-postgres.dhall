let T = ../schema/types.dhall
let S = ../schema/sql.dhall
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
                , (P.statWithThreshold "Pool waiting" (S.statGauge "pgrst_db_pool_waiting") T.thresholdErrors)
                , (P.statWithThreshold "Pool timeouts" "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) as rate FROM ${S.sum} WHERE MetricName = 'pgrst_db_pool_timeouts_total' AND TimeUnix > now() - INTERVAL 5 MINUTE ORDER BY TimeUnix) WHERE rate >= 0" T.thresholdErrors)
                , (P.stat "Schema cache query time" (S.statGauge "pgrst_schema_cache_query_time_seconds")) // { unit = T.Unit.Seconds }
                , P.statErrors "PG17 errors (5m)" "supabase-db.service"
                , P.statErrors "Auth errors (5m)" "supabase-auth.service"
                ]
            }
          , T.Row::{
            , title = "PostgREST Connection Pool"
            , panels =
                [ (P.timeseries "Pool connections (available / max)" T.Unit.Short
                    "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM ${S.gauge} WHERE MetricName IN ('pgrst_db_pool_available', 'pgrst_db_pool_max') AND ${S.tf} GROUP BY time, metric ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Pool waiting requests" T.Unit.Short
                    "SELECT TimeUnix as time, avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'pgrst_db_pool_waiting' AND ${S.tf} GROUP BY time ORDER BY time"
                  ) // { width = 8, thresholds = Some T.thresholdErrors }
                , (P.timeseries "Pool timeouts/interval" T.Unit.Short
                    "SELECT TimeUnix as time, runningDifference(Value) as value FROM ${S.sum} WHERE MetricName = 'pgrst_db_pool_timeouts_total' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"
                  ) // { width = 8, thresholds = Some T.thresholdErrors }
                ]
            }
          , T.Row::{
            , title = "PostgREST JWT & Schema Cache"
            , panels =
                [ (P.timeseries "JWT cache hit rate" T.Unit.Percentunit
                    "SELECT TimeUnix as time, if(sum(req.Value) > 0, sum(hit.Value) / sum(req.Value), 1) as value FROM ${S.sum} hit INNER JOIN ${S.sum} req ON hit.TimeUnix = req.TimeUnix WHERE hit.MetricName = 'pgrst_jwt_cache_hits_total' AND req.MetricName = 'pgrst_jwt_cache_requests_total' AND hit.${S.tf} GROUP BY time ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "JWT cache ops/sec" T.Unit.OpsPerSec
                    "SELECT time, metric, value FROM (SELECT TimeUnix as time, MetricName as metric, runningDifference(Value) / 30 as value FROM ${S.sum} WHERE MetricName IN ('pgrst_jwt_cache_requests_total', 'pgrst_jwt_cache_hits_total', 'pgrst_jwt_cache_evictions_total') AND ${S.tf} ORDER BY metric, time) WHERE value >= 0 ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Schema cache loads (success/fail)" T.Unit.Short
                    "SELECT TimeUnix as time, Attributes['status'] as status, runningDifference(Value) as value FROM ${S.sum} WHERE MetricName = 'pgrst_schema_cache_loads_total' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"
                  ) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "GoTrue / Auth"
            , panels =
                [ P.logVolume "Auth log volume by severity" "supabase-auth.service"
                , (P.timeseriesStacked "Auth events (login/signup/token/oauth2)" T.Unit.Short
                    "SELECT toStartOfMinute(Timestamp) as time, multiIf(Body LIKE '%login%' OR Body LIKE '%signin%', 'login', Body LIKE '%signup%' OR Body LIKE '%register%', 'signup', Body LIKE '%token%' OR Body LIKE '%refresh%', 'token', Body LIKE '%oauth%' OR Body LIKE '%oidc%', 'oauth', 'other') as event, count() as value FROM ${S.logs} WHERE ${S.unit} = 'supabase-auth.service' AND ${S.tfLog} AND (Body LIKE '%login%' OR Body LIKE '%signup%' OR Body LIKE '%token%' OR Body LIKE '%oauth%' OR Body LIKE '%signin%' OR Body LIKE '%register%' OR Body LIKE '%refresh%' OR Body LIKE '%oidc%') GROUP BY time, event ORDER BY time"
                  ) // { fillOpacity = 60 }
                ]
            }
          , T.Row::{
            , title = "Storage & Realtime"
            , panels =
                [ (P.logVolume "Storage API log volume" "supabase-storage.service") // { width = 8 }
                , (P.logVolume "Realtime log volume" "supabase-realtime.service") // { width = 8 }
                , (P.timeseries "Meta + Studio log volume" T.Unit.Short
                    "SELECT toStartOfMinute(Timestamp) as time, ${S.unit} as svc, count() as value FROM ${S.logs} WHERE ${S.unit} IN ('supabase-meta.service', 'supabase-studio.service') AND ${S.tfLog} GROUP BY time, svc ORDER BY time"
                  ) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "PostgreSQL 17"
            , panels =
                [ (P.logVolume "PG17 log volume by severity" "supabase-db.service") // { width = 24, height = 6 }
                ]
            }
          , T.Row::{
            , title = "All Errors"
            , panels =
                [ P.table "Supabase stack errors (all services)"
                    "SELECT Timestamp, ${S.unit} as unit, multiIf(${S.pri} <= 3, 'error', ${S.pri} = 4, 'warning', 'info') as level, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.unit} IN ('supabase-db.service', 'supabase-auth.service', 'supabase-rest.service', 'supabase-storage.service', 'supabase-meta.service', 'supabase-realtime.service', 'supabase-studio.service', 'supabase-imgproxy.service') AND ${S.isErr} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 200"
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
