let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let dashboard =
      T.Dashboard::{
      , title = "OCI Registry (Zot)"
      , uid = "oci-registry"
      , tags = [ "registry", "oci" ]
      , refresh = "1m"
      , timeFrom = "now-6h"
      , rows =
          [ T.Row::{
            , title = "Health"
            , panels =
                [ P.statLogs "Zot logs (6h)" "zot.service"
                , P.statErrors "Errors" "zot.service"
                , (P.stat "Pushes (PUT)" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'zot.service' AND Body LIKE '%PUT%' AND ${S.tfLog}")
                , (P.stat "Pulls (GET)" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'zot.service' AND Body LIKE '%GET%' AND Body LIKE '%blobs%' AND ${S.tfLog}")
                , (P.stat "Manifests served" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'zot.service' AND Body LIKE '%manifests%' AND ${S.tfLog}")
                , (P.statWithThreshold "4xx/5xx responses" "SELECT count() as value FROM ${S.logs} WHERE ${S.unit} = 'zot.service' AND (Body LIKE '%\" 4%' OR Body LIKE '%\" 5%') AND ${S.tfLog}" T.thresholdErrors)
                ]
            }
          , T.Row::{
            , title = "Traffic"
            , panels =
                [ P.timeseries "Request volume" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, count() as value FROM ${S.logs} WHERE ${S.unit} = 'zot.service' AND ${S.tfLog} GROUP BY time ORDER BY time"
                , (P.timeseriesStacked "Operations (push/pull/manifest/catalog)" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, multiIf(Body LIKE '%PUT%' AND Body LIKE '%blobs%', 'blob_push', Body LIKE '%PUT%' AND Body LIKE '%manifests%', 'manifest_push', Body LIKE '%GET%' AND Body LIKE '%blobs%', 'blob_pull', Body LIKE '%GET%' AND Body LIKE '%manifests%', 'manifest_pull', Body LIKE '%GET%' AND Body LIKE '%tags%', 'tag_list', 'other') as op, count() as value FROM ${S.logs} WHERE ${S.unit} = 'zot.service' AND (Body LIKE '%PUT%' OR Body LIKE '%GET%') AND ${S.tfLog} GROUP BY time, op ORDER BY time"
                  ) // { fillOpacity = 60 }
                ]
            }
          , T.Row::{
            , title = "Logs"
            , panels = [ P.logVolume "Log volume by severity" "zot.service" ]
            }
          , T.Row::{
            , title = "Errors"
            , panels =
                [ P.table "Registry errors & 4xx/5xx"
                    "SELECT Timestamp, substring(${S.msg}, 1, 400) as message FROM ${S.logs} WHERE ${S.unit} = 'zot.service' AND (${S.isErr} OR Body LIKE '%\" 4%' OR Body LIKE '%\" 5%') AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 100"
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
