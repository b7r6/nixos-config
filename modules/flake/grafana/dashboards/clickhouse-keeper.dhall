let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

-- filter to nodes that report keeper metrics (derived from the fleet, not hardcoded)
let keeperFilter = "${S.host} IN (SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE MetricName LIKE 'ClickHouseAsyncMetrics_Keeper%' AND TimeUnix > now() - INTERVAL 5 MINUTE)"
let kGauge = \(metric : Text) -> "SELECT TimeUnix as time, ${S.host} as keeper, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${keeperFilter} AND ${S.tf} GROUP BY time, keeper ORDER BY time"

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
                [ (P.stat "Nodes reporting" "SELECT uniq(${S.host}) as value FROM ${S.gauge} WHERE MetricName LIKE 'ClickHouseAsyncMetrics_Keeper%' AND TimeUnix > now() - INTERVAL 2 MINUTE") // { width = 4 }
                , (P.statWithThreshold "Synced followers" "SELECT max(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperSyncedFollowers' AND ${keeperFilter} AND TimeUnix > now() - INTERVAL 2 MINUTE" { mode = "absolute", steps = [ { color = "red", value = None Natural }, { color = "yellow", value = Some 1 }, { color = "green", value = Some 2 } ] }) // { width = 4 }
                , (P.statWithThreshold "Avg latency (leader)" "SELECT avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperAvgLatency' AND ${S.host} IN (SELECT ${S.host} FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperIsLeader' AND Value = 1 AND TimeUnix > now() - INTERVAL 2 MINUTE) AND TimeUnix > now() - INTERVAL 2 MINUTE" { mode = "absolute", steps = [ { color = "green", value = None Natural }, { color = "yellow", value = Some 100 }, { color = "red", value = Some 1000 } ] }) // { width = 4, unit = T.Unit.Milliseconds }
                , (P.stat "Commits/sec" "SELECT (max(Value) - min(Value)) / 60 as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperLastCommittedLogIdx' AND ${keeperFilter} AND TimeUnix > now() - INTERVAL 1 MINUTE") // { width = 4, unit = T.Unit.OpsPerSec }
                , (P.stat "Znodes" "SELECT max(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperZnodeCount' AND ${keeperFilter} AND TimeUnix > now() - INTERVAL 2 MINUTE") // { width = 4 }
                , (P.stat "Data size" "SELECT max(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperApproximateDataSize' AND ${keeperFilter} AND TimeUnix > now() - INTERVAL 2 MINUTE") // { width = 4, unit = T.Unit.Bytes }
                ]
            }
          , T.Row::{
            , title = "Raft Consensus"
            , panels =
                [ (P.timeseries "Commit rate (commits/sec per node)" T.Unit.OpsPerSec
                    "SELECT time, keeper, rate as value FROM (SELECT time, keeper, runningDifference(val) / 30 as rate FROM (SELECT toStartOfInterval(TimeUnix, INTERVAL 30 SECOND) as time, ${S.host} as keeper, max(Value) as val FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperLastCommittedLogIdx' AND ${keeperFilter} AND ${S.tf} GROUP BY time, keeper ORDER BY keeper, time)) WHERE rate >= 0 ORDER BY time"
                  ) // { width = 8, description = "how fast the ensemble is processing writes. all nodes should match (same log)." }
                , (P.timeseries "Inter-node log divergence" T.Unit.Short
                    "SELECT TimeUnix as time, max(Value) - min(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperLastCommittedLogIdx' AND ${keeperFilter} AND ${S.tf} GROUP BY time ORDER BY time"
                  ) // { width = 8, thresholds = Some { mode = "absolute", steps = [ { color = "green", value = None Natural }, { color = "yellow", value = Some 10 }, { color = "red", value = Some 100 } ] }, description = "max(idx) - min(idx) across nodes. 0 = perfectly in sync. >0 = replication lag." }
                , (P.timeseries "Raft lag (target - committed)" T.Unit.Short
                    "SELECT t.TimeUnix as time, t.${S.host} as keeper, avg(t.Value) - avg(c.Value) as value FROM ${S.gauge} t INNER JOIN ${S.gauge} c ON t.TimeUnix = c.TimeUnix AND t.${S.host} = c.${S.host} WHERE t.MetricName = 'ClickHouseAsyncMetrics_KeeperTargetCommitLogIdx' AND c.MetricName = 'ClickHouseAsyncMetrics_KeeperLastCommittedLogIdx' AND t.${S.tf} AND ${keeperFilter} GROUP BY time, keeper ORDER BY time"
                  ) // { width = 8, thresholds = Some T.thresholdErrors, description = "per-node gap between target and committed. non-zero = node is behind." }
                ]
            }
          , T.Row::{
            , title = "Latency"
            , panels =
                [ (P.timeseries "Avg request latency by node" T.Unit.Milliseconds
                    (kGauge "ClickHouseAsyncMetrics_KeeperAvgLatency")
                  ) // { width = 8, thresholds = Some { mode = "absolute", steps = [ { color = "green", value = None Natural }, { color = "yellow", value = Some 100 }, { color = "red", value = Some 1000 } ] } }
                , (P.timeseries "Max request latency by node" T.Unit.Milliseconds
                    (kGauge "ClickHouseAsyncMetrics_KeeperMaxLatency")
                  ) // { width = 8 }
                , (P.timeseries "Latency spread (max - min across nodes)" T.Unit.Milliseconds
                    "SELECT TimeUnix as time, max(Value) - min(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperAvgLatency' AND ${keeperFilter} AND ${S.tf} GROUP BY time ORDER BY time"
                  ) // { width = 8, description = "large spread = one node is slow (network? disk? CPU?)" }
                ]
            }
          , T.Row::{
            , title = "Leadership & Roles"
            , panels =
                [ (P.timeseries "Leader (1) / Follower (0) by node" T.Unit.Short
                    (kGauge "ClickHouseAsyncMetrics_KeeperIsLeader")
                  ) // { width = 12, description = "leadership changes visible as transitions. stable = 1 leader, N-1 followers." }
                , (P.timeseries "Synced followers (from leader)" T.Unit.Short
                    (kGauge "ClickHouseAsyncMetrics_KeeperSyncedFollowers")
                  ) // { width = 12, thresholds = Some { mode = "absolute", steps = [ { color = "red", value = None Natural }, { color = "yellow", value = Some 1 }, { color = "green", value = Some 2 } ] } }
                ]
            }
          , T.Row::{
            , title = "State (Znodes / Watches / Ephemerals)"
            , panels =
                [ (P.timeseries "Znode count by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperZnodeCount")) // { width = 8, description = "should be identical across all nodes (replicated state)" }
                , (P.timeseries "Watch count by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperWatchCount")) // { width = 8 }
                , (P.timeseries "Ephemeral count by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperEphemeralsCount")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Memory & Storage"
            , panels =
                [ (P.timeseries "Data size by node" T.Unit.Bytes (kGauge "ClickHouseAsyncMetrics_KeeperApproximateDataSize")) // { width = 8 }
                , (P.timeseries "Key arena size by node" T.Unit.Bytes (kGauge "ClickHouseAsyncMetrics_KeeperKeyArenaSize")) // { width = 8 }
                , (P.timeseries "Commit log cache by node" T.Unit.Bytes (kGauge "ClickHouseAsyncMetrics_KeeperCommitLogsCacheSize")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Connections & Resources"
            , panels =
                [ (P.timeseries "Sessions with watches by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperSessionWithWatches")) // { width = 8 }
                , (P.timeseries "Open FDs by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperOpenFileDescriptorCount")) // { width = 8 }
                , (P.timeseries "TCP rejected by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperTCPRejectedConnections"))
                    // { width = 8, thresholds = Some T.thresholdErrors, description = "non-zero = connections being refused. capacity issue." }
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
