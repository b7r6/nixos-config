let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let dashboard =
      T.Dashboard::{
      , title = "Kanidm / Identity"
      , uid = "kanidm-identity"
      , tags = [ "kanidm", "identity" ]
      , refresh = "1m"
      , timeFrom = "now-6h"
      , rows =
          [ T.Row::{
            , title = "Health"
            , panels =
                [ P.statLogs "Kanidm logs (6h)" "kanidm.service"
                , P.statErrors "Kanidm errors" "kanidm.service"
                , (P.stat "Auth attempts"
                    "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'kanidm.service' AND (Body LIKE '%auth%' OR Body LIKE '%credential%' OR Body LIKE '%passkey%') AND ${S.tfLog}"
                  )
                , (P.stat "OIDC flows"
                    "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'kanidm.service' AND (Body LIKE '%oauth2%' OR Body LIKE '%openid%' OR Body LIKE '%authorization_code%') AND ${S.tfLog}"
                  )
                , P.statErrors "Litestream errors" "litestream.service"
                , (P.stat "Litestream WAL syncs"
                    "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'litestream.service' AND (Body LIKE '%wal%' OR Body LIKE '%snapshot%' OR Body LIKE '%sync%') AND ${S.tfLog}"
                  )
                ]
            }
          , T.Row::{
            , title = "Authentication"
            , panels =
                [ P.logVolume "Kanidm log volume" "kanidm.service"
                , (P.timeseriesStacked "Auth event breakdown" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%passkey%' OR Body LIKE '%webauthn%', 'passkey', Body LIKE '%password%' OR Body LIKE '%credential%', 'password', Body LIKE '%oauth2%' OR Body LIKE '%openid%', 'oauth2', Body LIKE '%token%', 'token', 'other_auth') as method, count() as value FROM ${S.logs} WHERE ${S.unit} = 'kanidm.service' AND (Body LIKE '%auth%' OR Body LIKE '%credential%' OR Body LIKE '%passkey%' OR Body LIKE '%token%' OR Body LIKE '%oauth2%' OR Body LIKE '%openid%' OR Body LIKE '%webauthn%' OR Body LIKE '%password%') AND ${S.tfLog} GROUP BY time, method ORDER BY time"
                  ) // { fillOpacity = 60 }
                ]
            }
          , T.Row::{
            , title = "OIDC / OAuth2"
            , panels =
                [ P.timeseries "OIDC authorization events" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, count() as value FROM ${S.logs} WHERE ${S.unit} = 'kanidm.service' AND (Body LIKE '%authorization_code%' OR Body LIKE '%oauth2%consent%' OR Body LIKE '%token_exchange%') AND ${S.tfLog} GROUP BY time ORDER BY time"
                , (P.timeseries "Failed auth attempts" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, count() as value FROM ${S.logs} WHERE ${S.unit} = 'kanidm.service' AND (Body LIKE '%invalid%' OR Body LIKE '%denied%' OR Body LIKE '%failed%' OR Body LIKE '%reject%') AND ${S.isWarn} AND ${S.tfLog} GROUP BY time ORDER BY time"
                  ) // { thresholds = Some T.thresholdErrors }
                ]
            }
          , T.Row::{
            , title = "Litestream (SQLite -> R2)"
            , panels =
                [ P.logVolume "Litestream log volume" "litestream.service"
                , P.timeseries "Replication events (WAL sync / snapshot)" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%snapshot%', 'snapshot', Body LIKE '%wal%', 'wal_sync', 'other') as event, count() as value FROM ${S.logs} WHERE ${S.unit} = 'litestream.service' AND (Body LIKE '%wal%' OR Body LIKE '%snapshot%' OR Body LIKE '%sync%') AND ${S.tfLog} GROUP BY time, event ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Errors & Audit"
            , panels =
                [ (P.table "Kanidm errors & warnings"
                    "SELECT Timestamp, multiIf(${S.pri} <= 3, 'error', ${S.pri} = 4, 'warning', 'info') as level, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.unit} = 'kanidm.service' AND ${S.isWarn} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 100"
                  ) // { height = 8 }
                , (P.table "Litestream errors"
                    (S.logErrors "litestream.service" 50)
                  ) // { height = 8 }
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
