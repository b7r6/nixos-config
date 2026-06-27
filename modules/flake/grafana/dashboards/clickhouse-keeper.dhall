let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

-- filter to nodes that report keeper metrics (derived from the fleet, not hardcoded)
let keeperFilter = "${S.host} IN (SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE MetricName LIKE 'ClickHouseAsyncMetrics_Keeper%' AND TimeUnix > now() - INTERVAL 5 MINUTE)"
let kGauge = \(metric : Text) -> "SELECT TimeUnix as time, ${S.host} as keeper, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${keeperFilter} AND ${S.tf} GROUP BY time, keeper ORDER BY time"
let kStat = \(metric : Text) -> "SELECT ${S.host} as keeper, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${keeperFilter} AND TimeUnix > now() - INTERVAL 2 MINUTE GROUP BY keeper"

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
                , (P.stat "Znode count" "SELECT avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperZnodeCount' AND ${keeperFilter} AND TimeUnix > now() - INTERVAL 2 MINUTE") // { width = 4 }
                , (P.stat "Watches" "SELECT sum(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperWatchCount' AND ${keeperFilter} AND TimeUnix > now() - INTERVAL 2 MINUTE") // { width = 4 }
                , (P.stat "Ephemerals" "SELECT sum(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperEphemeralsCount' AND ${keeperFilter} AND TimeUnix > now() - INTERVAL 2 MINUTE") // { width = 4 }
                , (P.stat "Data size" "SELECT avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseAsyncMetrics_KeeperApproximateDataSize' AND ${keeperFilter} AND TimeUnix > now() - INTERVAL 2 MINUTE") // { width = 4, unit = T.Unit.Bytes }
                ]
            }
          , T.Row::{
            , title = "Latency"
            , panels =
                [ (P.timeseries "Avg latency by node" T.Unit.Milliseconds (kGauge "ClickHouseAsyncMetrics_KeeperAvgLatency")) // { width = 8 }
                , (P.timeseries "Max latency by node" T.Unit.Milliseconds (kGauge "ClickHouseAsyncMetrics_KeeperMaxLatency")) // { width = 8 }
                , (P.timeseries "Min latency by node" T.Unit.Milliseconds (kGauge "ClickHouseAsyncMetrics_KeeperMinLatency")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Throughput"
            , panels =
                [ P.timeseries "Packets received by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperPacketsReceived")
                , P.timeseries "Packets sent by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperPacketsSent")
                ]
            }
          , T.Row::{
            , title = "Raft Log"
            , panels =
                [ P.timeseries "Last committed log idx" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperLastCommittedLogIdx")
                , P.timeseries "Target commit log idx" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperTargetCommitLogIdx")
                , P.timeseries "Last snapshot idx" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperLastSnapshotIdx")
                ]
            }
          , T.Row::{
            , title = "Replication & Roles"
            , panels =
                [ P.timeseries "IsLeader by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperIsLeader")
                , P.timeseries "IsFollower by node" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperIsFollower")
                , P.timeseries "Synced followers" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperSyncedFollowers")
                ]
            }
          , T.Row::{
            , title = "State"
            , panels =
                [ P.timeseries "Znode count" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperZnodeCount")
                , P.timeseries "Watch count" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperWatchCount")
                , P.timeseries "Ephemeral count" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperEphemeralsCount")
                ]
            }
          , T.Row::{
            , title = "Memory & Storage"
            , panels =
                [ (P.timeseries "Approximate data size" T.Unit.Bytes (kGauge "ClickHouseAsyncMetrics_KeeperApproximateDataSize")) // { width = 8 }
                , (P.timeseries "Key arena size" T.Unit.Bytes (kGauge "ClickHouseAsyncMetrics_KeeperKeyArenaSize")) // { width = 8 }
                , (P.timeseries "Commit logs cache size" T.Unit.Bytes (kGauge "ClickHouseAsyncMetrics_KeeperCommitLogsCacheSize")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Connections & Resources"
            , panels =
                [ P.timeseries "Sessions with watches" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperSessionWithWatches")
                , P.timeseries "Open file descriptors" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperOpenFileDescriptorCount")
                , (P.timeseries "TCP rejected connections" T.Unit.Short (kGauge "ClickHouseAsyncMetrics_KeeperTCPRejectedConnections"))
                    // { thresholds = Some T.thresholdErrors }
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
