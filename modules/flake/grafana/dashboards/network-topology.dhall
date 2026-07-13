-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                    // hypermodern // grafana // network-topology
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- fleet network: throughput, errors, drops, connections per host.
-- tailscale interface isolated for inter-node traffic visibility.
let T = ../schema/types.dhall

let S = ../schema/sql.dhall

let Q = ../schema/queries.dhall

let P = ../schema/panels.dhall

let R = ../schema/render.dhall

let netRate =
      \(dir : Text) ->
        Q.rateBucketed
          "system.network.io"
          "Attributes['direction'] = '${dir}' AND Attributes['device'] != 'lo'"
          "${S.host} as host, Attributes['device'] as dev"
          "host"

let netErrRate =
      \(metric : Text) ->
        Q.rateBucketed
          metric
          "1=1"
          "${S.host} as host, Attributes['device'] as dev"
          "host"

let tailscaleRate =
      \(dir : Text) ->
        "SELECT time, host, rate as value FROM (SELECT time, host, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${S.host} as host, max(Value) as val FROM ${S.sum} WHERE MetricName = 'system.network.io' AND Attributes['device'] = 'tailscale0' AND Attributes['direction'] = '${dir}' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, host ORDER BY host, time)) WHERE rate >= 0 ORDER BY time"

let hostVar =
      T.Variable::{
      , name = "host"
      , label = "Host"
      , type = T.VariableType.Query
      , query =
          "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1"
      , includeAll = True
      }

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
            [ P.timeseries "TX by host" T.Unit.BytesPerSec (netRate "transmit")
            , P.timeseries "RX by host" T.Unit.BytesPerSec (netRate "receive")
            ]
          }
        , T.Row::{
          , title = "Errors & Drops"
          , panels =
            [     P.timeseries
                    "Errors by host"
                    T.Unit.Short
                    (netErrRate "system.network.errors")
              //  { thresholds = Some T.thresholdErrors }
            ,     P.timeseries
                    "Drops by host"
                    T.Unit.Short
                    (netErrRate "system.network.dropped")
              //  { thresholds = Some T.thresholdErrors }
            ]
          }
        , T.Row::{
          , title = "Connections"
          , panels =
            [     P.timeseries
                    "Active TCP by host"
                    T.Unit.Short
                    ( Q.sumByHost
                        "system.network.connections"
                        "Attributes['protocol'] = 'tcp'"
                    )
              //  { width = 24 }
            ]
          }
        , T.Row::{
          , title = "Tailscale"
          , panels =
            [ P.timeseries
                "Tailscale TX"
                T.Unit.BytesPerSec
                (tailscaleRate "transmit")
            , P.timeseries
                "Tailscale RX"
                T.Unit.BytesPerSec
                (tailscaleRate "receive")
            ]
          }
        ]
      }

in  R.renderDashboard dashboard
