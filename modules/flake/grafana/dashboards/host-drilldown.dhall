-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                    // hypermodern // grafana // host-drilldown
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- deep dive into a single host. every OTel scraper gets a panel.

let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let Q = ../schema/queries.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let hostVar =
      T.Variable::{
      , name = "host"
      , label = "Host"
      , type = T.VariableType.Query
      , query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1"
      , includeAll = False
      }

let dashboard =
      T.Dashboard::{
      , title = "Host Drill-Down"
      , uid = "host-drilldown"
      , tags = [ "fleet", "host" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , variables = [ hostVar ]
      , rows =

          [ -- ── CPU ────────────────────────────────────────────────────────────
            T.Row::{
            , title = "CPU"
            , panels =
                [ (P.timeseriesStacked "CPU time by state" T.Unit.Seconds
                    (Q.rateBucketedForHost "system.cpu.time" "1=1"
                      "Attributes['state'] as state, Attributes['cpu'] as cpu"
                      "state")
                  )

                , (P.timeseries "Load averages (1m / 5m / 15m)" T.Unit.Short
                    "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM ${S.gauge} WHERE MetricName LIKE 'system.cpu.load_average%' AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time, metric ORDER BY time"
                  ) // { thresholds = Some T.thresholdLoad }
                ]
            }

          , -- ── memory ─────────────────────────────────────────────────────────
            T.Row::{
            , title = "Memory"
            , panels =
                [ P.timeseriesStacked "Memory by state" T.Unit.Bytes
                    (Q.sumByAttrForHost "system.memory.usage" "state" "state" "1=1")

                , P.timeseries "Paging (swap I/O)" T.Unit.Bytes
                    (Q.rateBucketedForHost "system.paging.operations" "1=1"
                      "Attributes['direction'] as dir, Attributes['type'] as type"
                      "dir, type")
                ]
            }

          , -- ── disk ───────────────────────────────────────────────────────────
            T.Row::{
            , title = "Disk"
            , panels =
                [ P.timeseries "Disk I/O by device" T.Unit.BytesPerSec
                    (Q.rateBucketedForHost "system.disk.io" "1=1"
                      "Attributes['device'] as device, Attributes['direction'] as dir"
                      "device, dir")

                , (P.timeseriesStacked "Filesystem usage by mount" T.Unit.Bytes
                    (Q.sumByAttrForHost "system.filesystem.usage" "mountpoint" "mount"
                      "Attributes['mountpoint'] NOT LIKE '/nix%'")
                  ) // { fillOpacity = 60 }
                ]
            }

          , -- ── network ────────────────────────────────────────────────────────
            T.Row::{
            , title = "Network"
            , panels =
                [ P.timeseries "Network I/O by interface" T.Unit.BytesPerSec
                    (Q.rateBucketedForHost "system.network.io" "Attributes['device'] != 'lo'"
                      "Attributes['device'] as iface, Attributes['direction'] as dir"
                      "iface, dir")

                , P.timeseries "Network errors + drops" T.Unit.Short
                    (Q.rateBucketedForHost "system.network.errors" "1=1"
                      "MetricName as metric, Attributes['device'] as iface"
                      "metric, iface")
                ]
            }

          , -- ── logs ───────────────────────────────────────────────────────────
            T.Row::{
            , title = "Logs"
            , panels =
                [ (P.timeseriesStacked "Log rate by severity" T.Unit.Short
                    "SELECT toStartOfMinute(Timestamp) as time, ${S.severityExpr} as severity, count() as value FROM ${S.logs} WHERE ${S.hostFilterSingle} AND ${S.tfLog} GROUP BY time, severity ORDER BY time"
                  ) // { width = 24, height = 5 }

                , (P.table "Recent logs"
                    "SELECT Timestamp, multiIf(${S.pri} <= 3, 'error', ${S.pri} = 4, 'warning', 'info') as level, ${S.unit} as unit, substring(${S.msg}, 1, 300) as message FROM ${S.logs} WHERE ${S.hostFilterSingle} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 500"
                  ) // { height = 12 }
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
