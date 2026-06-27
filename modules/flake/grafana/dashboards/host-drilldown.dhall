let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let hostVar = T.Variable::{ name = "host", label = "Host", type = T.VariableType.Query, query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1", includeAll = False }

let dashboard =
      T.Dashboard::{
      , title = "Host Drill-Down"
      , uid = "host-drilldown"
      , tags = [ "fleet", "host" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , variables = [ hostVar ]
      , rows =
          [ T.Row::{
            , title = "CPU"
            , panels =
                [ (P.timeseriesStacked "CPU time by state" T.Unit.Seconds
                    "SELECT time, state, sum(rate) as value FROM (SELECT time, state, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, Attributes['state'] as state, Attributes['cpu'] as cpu, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.cpu.time' AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time, state, cpu ORDER BY cpu, state, time)) WHERE rate >= 0 GROUP BY time, state ORDER BY time"
                  )
                , (P.timeseries "Load averages (1m / 5m / 15m)" T.Unit.Short
                    "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM ${S.gauge} WHERE MetricName LIKE 'system.cpu.load_average%' AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time, metric ORDER BY time"
                  ) // { thresholds = Some T.thresholdLoad }
                ]
            }
          , T.Row::{
            , title = "Memory"
            , panels =
                [ P.timeseriesStacked "Memory by state" T.Unit.Bytes
                    "SELECT TimeUnix as time, Attributes['state'] as state, avg(Value) as value FROM ${S.sum} WHERE MetricName = 'system.memory.usage' AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time, state ORDER BY time"
                , P.timeseries "Paging (swap I/O)" T.Unit.Bytes
                    "SELECT time, dir, type, value FROM (SELECT time, dir, type, runningDifference(val) / 30 as value FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, Attributes['direction'] as dir, Attributes['type'] as type, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.paging.operations' AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time, dir, type ORDER BY dir, type, time)) WHERE value >= 0 ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Disk"
            , panels =
                [ P.timeseries "Disk I/O by device" T.Unit.BytesPerSec
                    "SELECT time, device, dir, value FROM (SELECT time, device, dir, runningDifference(val) / 30 as value FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, Attributes['device'] as device, Attributes['direction'] as dir, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.disk.io' AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time, device, dir ORDER BY device, dir, time)) WHERE value >= 0 ORDER BY time"
                , (P.timeseriesStacked "Filesystem usage by mount" T.Unit.Bytes
                    "SELECT TimeUnix as time, Attributes['mountpoint'] as mount, Attributes['state'] as state, avg(Value) as value FROM ${S.sum} WHERE MetricName = 'system.filesystem.usage' AND ${S.hostFilterSingle} AND Attributes['mountpoint'] NOT LIKE '/nix%' AND ${S.tf} GROUP BY time, mount, state ORDER BY time"
                  ) // { fillOpacity = 60 }
                ]
            }
          , T.Row::{
            , title = "Network"
            , panels =
                [ P.timeseries "Network I/O by interface" T.Unit.BytesPerSec
                    "SELECT time, iface, dir, value FROM (SELECT time, iface, dir, runningDifference(val) / 30 as value FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, Attributes['device'] as iface, Attributes['direction'] as dir, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.network.io' AND ${S.hostFilterSingle} AND Attributes['device'] != 'lo' AND ${S.tf} GROUP BY time, iface, dir ORDER BY iface, dir, time)) WHERE value >= 0 ORDER BY time"
                , P.timeseries "Network errors + drops" T.Unit.Short
                    "SELECT time, metric, iface, value FROM (SELECT time, metric, iface, runningDifference(val) / 30 as value FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, MetricName as metric, Attributes['device'] as iface, max(Value) as val FROM ${S.sum} WHERE MetricName IN ('system.network.errors', 'system.network.dropped') AND ${S.hostFilterSingle} AND ${S.tf} GROUP BY time, metric, iface ORDER BY iface, metric, time)) WHERE value >= 0 ORDER BY time"
                ]
            }
          , T.Row::{
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
