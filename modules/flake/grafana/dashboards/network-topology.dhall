let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let hostVar = T.Variable::{ name = "host", label = "Host", type = T.VariableType.Query, query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1", includeAll = True }

let dashboard =
      T.Dashboard::{
      , title = "Network Topology"
      , uid = "network-topology"
      , tags = [ "fleet", "network" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , variables = [ hostVar ]
      , rows =
          [ T.Row::{
            , title = "Throughput"
            , panels =
                [ P.timeseries "TX by host (excl. loopback)" T.Unit.BytesPerSec
                    "SELECT time, host, sum(rate) as value FROM (SELECT time, host, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${S.host} as host, Attributes['device'] as dev, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.network.io' AND Attributes['direction'] = 'transmit' AND Attributes['device'] != 'lo' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host, dev ORDER BY host, dev, time)) WHERE rate >= 0 GROUP BY time, host ORDER BY time"
                , P.timeseries "RX by host (excl. loopback)" T.Unit.BytesPerSec
                    "SELECT time, host, sum(rate) as value FROM (SELECT time, host, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${S.host} as host, Attributes['device'] as dev, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.network.io' AND Attributes['direction'] = 'receive' AND Attributes['device'] != 'lo' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host, dev ORDER BY host, dev, time)) WHERE rate >= 0 GROUP BY time, host ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Errors & Drops"
            , panels =
                [ (P.timeseries "Network errors by host" T.Unit.Short
                    "SELECT time, host, sum(rate) as value FROM (SELECT time, host, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${S.host} as host, Attributes['device'] as dev, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.network.errors' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host, dev ORDER BY host, dev, time)) WHERE rate >= 0 GROUP BY time, host ORDER BY time"
                  ) // { thresholds = Some T.thresholdErrors }
                , (P.timeseries "Dropped packets by host" T.Unit.Short
                    "SELECT time, host, sum(rate) as value FROM (SELECT time, host, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${S.host} as host, Attributes['device'] as dev, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.network.dropped' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host, dev ORDER BY host, dev, time)) WHERE rate >= 0 GROUP BY time, host ORDER BY time"
                  ) // { thresholds = Some T.thresholdErrors }
                ]
            }
          , T.Row::{
            , title = "Connections"
            , panels =
                [ (P.timeseries "Active TCP connections by host" T.Unit.Short
                    "SELECT TimeUnix as time, ${S.host} as host, sum(Value) as value FROM ${S.sum} WHERE MetricName = 'system.network.connections' AND Attributes['protocol'] = 'tcp' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host ORDER BY time"
                  ) // { width = 24 }
                ]
            }
          , T.Row::{
            , title = "Tailscale Interface"
            , panels =
                [ P.timeseries "Tailscale TX" T.Unit.BytesPerSec
                    "SELECT time, host, rate as value FROM (SELECT time, host, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${S.host} as host, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.network.io' AND Attributes['device'] = 'tailscale0' AND Attributes['direction'] = 'transmit' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host ORDER BY host, time)) WHERE rate >= 0 ORDER BY time"
                , P.timeseries "Tailscale RX" T.Unit.BytesPerSec
                    "SELECT time, host, rate as value FROM (SELECT time, host, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${S.host} as host, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.network.io' AND Attributes['device'] = 'tailscale0' AND Attributes['direction'] = 'receive' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host ORDER BY host, time)) WHERE rate >= 0 ORDER BY time"
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
