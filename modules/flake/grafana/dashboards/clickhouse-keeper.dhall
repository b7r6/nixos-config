-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                    // hypermodern // grafana // clickhouse-keeper
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- 3-node raft ensemble. the coordination plane for all replicated state.
-- nodes auto-discovered from metrics (no hardcoded hostnames).
let T = ../schema/types.dhall

let S = ../schema/sql.dhall

let P = ../schema/panels.dhall

let R = ../schema/render.dhall

let k = "ClickHouseAsyncMetrics_Keeper"

let ensemble =
      "${S.host} IN (SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE MetricName LIKE '${k}%' AND TimeUnix > now() - INTERVAL 5 MINUTE)"

let byNode =
      \(metric : Text) ->
        "SELECT TimeUnix as time, ${S.host} as keeper, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${k}${metric}' AND ${ensemble} AND ${S.tf} GROUP BY time, keeper ORDER BY time"

let recent =
      \(metric : Text) ->
      \(agg : Text) ->
        "SELECT ${agg}(Value) as value FROM ${S.gauge} WHERE MetricName = '${k}${metric}' AND ${ensemble} AND TimeUnix > now() - INTERVAL 2 MINUTE"

let spread =
      \(metric : Text) ->
        "SELECT TimeUnix as time, max(Value) - min(Value) as value FROM ${S.gauge} WHERE MetricName = '${k}${metric}' AND ${ensemble} AND ${S.tf} GROUP BY time ORDER BY time"

let thresholdLatency =
      { mode = "absolute"
      , steps =
        [ { color = "green", value = None Natural }
        , { color = "yellow", value = Some 100 }
        , { color = "red", value = Some 1000 }
        ]
      }

let thresholdFollowers =
      { mode = "absolute"
      , steps =
        [ { color = "red", value = None Natural }
        , { color = "yellow", value = Some 1 }
        , { color = "green", value = Some 2 }
        ]
      }

let thresholdDivergence =
      { mode = "absolute"
      , steps =
        [ { color = "green", value = None Natural }
        , { color = "yellow", value = Some 10 }
        , { color = "red", value = Some 100 }
        ]
      }

let commitRate =
      ''
      SELECT time, keeper, rate as value
      FROM (
        SELECT time, keeper, runningDifference(val) / 30 as rate
        FROM (
          SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time,
                 ${S.host} as keeper,
                 max(Value) as val
          FROM ${S.gauge}
          WHERE MetricName = '${k}LastCommittedLogIdx'
            AND ${ensemble}
            AND ${S.tf}
          GROUP BY time, keeper
          ORDER BY keeper, time
        )
      )
      WHERE rate >= 0
      ORDER BY time
      ''

let raftLag =
      ''
      SELECT t.TimeUnix as time,
             t.${S.host} as keeper,
             avg(t.Value) - avg(c.Value) as value
      FROM ${S.gauge} t
      INNER JOIN ${S.gauge} c
        ON t.TimeUnix = c.TimeUnix
        AND t.${S.host} = c.${S.host}
      WHERE t.MetricName = '${k}TargetCommitLogIdx'
        AND c.MetricName = '${k}LastCommittedLogIdx'
        AND t.${S.tf}
        AND ${ensemble}
      GROUP BY time, keeper
      ORDER BY time
      ''

let leaderLatency =
      ''
      SELECT avg(Value) as value
      FROM ${S.gauge}
      WHERE MetricName = '${k}AvgLatency'
        AND ${S.host} IN (
          SELECT ${S.host} FROM ${S.gauge}
          WHERE MetricName = '${k}IsLeader'
            AND Value = 1
            AND TimeUnix > now() - INTERVAL 2 MINUTE
        )
        AND TimeUnix > now() - INTERVAL 2 MINUTE
      ''

let dashboard =
      T.Dashboard::{
      , title = "ClickHouse Keeper"
      , uid = "clickhouse-keeper"
      , tags = [ "clickhouse", "keeper", "zookeeper" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , rows =
        [ T.Row::{
          , title = "Ensemble Health"
          , panels =
            [     P.stat
                    "Nodes reporting"
                    "SELECT uniq(${S.host}) as value FROM ${S.gauge} WHERE MetricName LIKE '${k}%' AND TimeUnix > now() - INTERVAL 2 MINUTE"
              //  { width = 4 }
            ,     P.statWithThreshold
                    "Synced followers"
                    (recent "SyncedFollowers" "max")
                    thresholdFollowers
              //  { width = 4 }
            ,     P.statWithThreshold
                    "Leader latency"
                    leaderLatency
                    thresholdLatency
              //  { width = 4, unit = T.Unit.Milliseconds }
            ,     P.stat
                    "Commits/sec"
                    "SELECT (max(Value) - min(Value)) / 60 as value FROM ${S.gauge} WHERE MetricName = '${k}LastCommittedLogIdx' AND ${ensemble} AND TimeUnix > now() - INTERVAL 1 MINUTE"
              //  { width = 4, unit = T.Unit.OpsPerSec }
            , P.stat "Znodes" (recent "ZnodeCount" "max") // { width = 4 }
            ,     P.stat "Data size" (recent "ApproximateDataSize" "max")
              //  { width = 4, unit = T.Unit.Bytes }
            ]
          }
        , T.Row::{
          , title = "Raft Consensus"
          , panels =
            [     P.timeseries
                    "Commit rate per node"
                    T.Unit.OpsPerSec
                    commitRate
              //  { width = 8
                  , description =
                      "writes/sec. all nodes should overlap (same replicated log)."
                  }
            ,     P.timeseries
                    "Inter-node divergence"
                    T.Unit.Short
                    (spread "LastCommittedLogIdx")
              //  { width = 8
                  , thresholds = Some thresholdDivergence
                  , description = "max - min log idx across nodes. 0 = in sync."
                  }
            ,     P.timeseries
                    "Raft lag (target - committed)"
                    T.Unit.Short
                    raftLag
              //  { width = 8
                  , thresholds = Some T.thresholdErrors
                  , description =
                      "per-node backlog. non-zero = that node is behind."
                  }
            ]
          }
        , T.Row::{
          , title = "Latency"
          , panels =
            [     P.timeseries
                    "Avg latency by node"
                    T.Unit.Milliseconds
                    (byNode "AvgLatency")
              //  { width = 8, thresholds = Some thresholdLatency }
            ,     P.timeseries
                    "Max latency by node"
                    T.Unit.Milliseconds
                    (byNode "MaxLatency")
              //  { width = 8 }
            ,     P.timeseries
                    "Latency spread"
                    T.Unit.Milliseconds
                    (spread "AvgLatency")
              //  { width = 8
                  , description =
                      "max - min across nodes. spike = one node slow."
                  }
            ]
          }
        , T.Row::{
          , title = "Leadership"
          , panels =
            [     P.timeseries
                    "Leader / Follower by node"
                    T.Unit.Short
                    (byNode "IsLeader")
              //  { width = 12
                  , description = "1 = leader. transitions = elections."
                  }
            ,     P.timeseries
                    "Synced followers"
                    T.Unit.Short
                    (byNode "SyncedFollowers")
              //  { width = 12, thresholds = Some thresholdFollowers }
            ]
          }
        , T.Row::{
          , title = "Replicated State"
          , panels =
            [     P.timeseries "Znodes" T.Unit.Short (byNode "ZnodeCount")
              //  { width = 8
                  , description = "identical across nodes = consistent."
                  }
            ,     P.timeseries "Watches" T.Unit.Short (byNode "WatchCount")
              //  { width = 8 }
            ,     P.timeseries
                    "Ephemerals"
                    T.Unit.Short
                    (byNode "EphemeralsCount")
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "Memory"
          , panels =
            [     P.timeseries
                    "Data size"
                    T.Unit.Bytes
                    (byNode "ApproximateDataSize")
              //  { width = 8 }
            ,     P.timeseries "Key arena" T.Unit.Bytes (byNode "KeyArenaSize")
              //  { width = 8 }
            ,     P.timeseries
                    "Commit log cache"
                    T.Unit.Bytes
                    (byNode "CommitLogsCacheSize")
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "Connections"
          , panels =
            [     P.timeseries
                    "Sessions with watches"
                    T.Unit.Short
                    (byNode "SessionWithWatches")
              //  { width = 8 }
            ,     P.timeseries
                    "Open FDs"
                    T.Unit.Short
                    (byNode "OpenFileDescriptorCount")
              //  { width = 8 }
            ,     P.timeseries
                    "TCP rejected"
                    T.Unit.Short
                    (byNode "TCPRejectedConnections")
              //  { width = 8
                  , thresholds = Some T.thresholdErrors
                  , description =
                      "non-zero = connections refused. capacity issue."
                  }
            ]
          }
        ]
      }

in  R.renderDashboard dashboard
