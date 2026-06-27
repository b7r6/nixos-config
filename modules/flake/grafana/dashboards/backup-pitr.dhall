let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let hostVar = T.Variable::{ name = "host", label = "Host", type = T.VariableType.Query, query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1", includeAll = True }

let dashboard =
      T.Dashboard::{
      , title = "Backup & PITR"
      , uid = "backup-pitr"
      , tags = [ "backup", "pitr" ]
      , refresh = "5m"
      , timeFrom = "now-24h"
      , variables = [ hostVar ]
      , rows =
          [ T.Row::{
            , title = "Health"
            , panels =
                [ (P.stat "pgbackrest events" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'pgbackrest%' AND ${S.tfLog}")
                , (P.statWithThreshold "pgbackrest errors" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'pgbackrest%' AND ${S.isErr} AND ${S.tfLog}" T.thresholdErrors)
                , (P.stat "Restic events" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'restic%' AND ${S.tfLog}")
                , (P.statWithThreshold "Restic errors" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'restic%' AND ${S.isErr} AND ${S.tfLog}" T.thresholdErrors)
                , (P.stat "Litestream events" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'litestream.service' AND ${S.tfLog}")
                , (P.stat "PG dump events" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'supabase-db-dump.service' AND ${S.tfLog}")
                ]
            }
          , T.Row::{
            , title = "pgBackRest (PG17 PITR -> R2)"
            , panels =
                [ P.logVolume "pgBackRest log activity" "pgbackrest-backup-diff.service"
                , P.timeseries "pgBackRest activity (file logs + journal)" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%archive-push%', 'archive-push', Body LIKE '%backup%' AND Body LIKE '%full%', 'full', Body LIKE '%backup%', 'diff', Body LIKE '%expire%', 'expire', 'other') as op, count() as value FROM ${S.logs} WHERE (Body LIKE '%pgbackrest%' OR ${S.unit} LIKE 'pgbackrest%' OR ${S.unit} LIKE 'supabase-pgbackrest%') AND ${S.tfLog} GROUP BY time, op ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Restic (File Backups -> R2)"
            , panels =
                [ P.timeseries "Restic backup activity by host" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, ${S.host} as node, count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'restic%' AND ${S.tfLog} AND ${S.hostFilter} GROUP BY time, node ORDER BY time"
                , (P.timeseriesStacked "Restic operations (backup/check/prune)" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%backup%' OR Body LIKE '%snapshot%', 'backup', Body LIKE '%check%' OR Body LIKE '%verify%', 'check', Body LIKE '%prune%' OR Body LIKE '%forget%', 'prune', 'other') as op, count() as value FROM ${S.logs} WHERE ${S.unit} LIKE 'restic%' AND (Body LIKE '%backup%' OR Body LIKE '%snapshot%' OR Body LIKE '%check%' OR Body LIKE '%prune%' OR Body LIKE '%forget%' OR Body LIKE '%verify%') AND ${S.tfLog} GROUP BY time, op ORDER BY time"
                  ) // { fillOpacity = 60 }
                ]
            }
          , T.Row::{
            , title = "Litestream (Kanidm SQLite -> R2)"
            , panels =
                [ P.logVolume "Litestream replication events" "litestream.service"
                , P.logVolume "PG logical dump activity" "supabase-db-dump.service"
                ]
            }
          , T.Row::{
            , title = "All Backup Errors"
            , panels =
                [ P.table "Backup errors (all systems)"
                    "SELECT Timestamp, ${S.host} as host, ${S.unit} as unit, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE (${S.unit} LIKE 'pgbackrest%' OR ${S.unit} LIKE 'restic%' OR ${S.unit} = 'litestream.service' OR ${S.unit} = 'supabase-db-dump.service') AND ${S.isErr} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 100"
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
