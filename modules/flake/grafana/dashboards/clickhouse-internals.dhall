let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let chRate = \(metric : Text) -> "SELECT TimeUnix as time, runningDifference(Value) / 30 as value FROM ${S.sum} WHERE MetricName = '${metric}' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"
let chGauge = \(metric : Text) -> "SELECT TimeUnix as time, avg(Value) as value FROM ${S.gauge} WHERE MetricName = '${metric}' AND ${S.tf} GROUP BY time ORDER BY time"
let chGaugeMulti = \(metrics : Text) -> "SELECT TimeUnix as time, MetricName as metric, avg(Value) as value FROM ${S.gauge} WHERE MetricName IN (${metrics}) AND ${S.tf} GROUP BY time, metric ORDER BY time"

let dashboard =
      T.Dashboard::{
      , title = "ClickHouse Internals"
      , uid = "clickhouse-internals"
      , tags = [ "clickhouse", "internals" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , rows =
          [ T.Row::{
            , title = "Server Health"
            , panels =
                [ (P.statGauge "Active queries" "ClickHouseMetrics_Query") // { width = 3 }
                , (P.stat "Uptime" (S.statGauge "ClickHouseAsyncMetrics_Uptime")) // { width = 3, unit = T.Unit.Seconds }
                , (P.stat "MergeTree size" (S.statGauge "ClickHouseAsyncMetrics_TotalBytesOfMergeTreeTables")) // { width = 3, unit = T.Unit.Bytes }
                , (P.statGauge "Total rows" "ClickHouseAsyncMetrics_TotalRowsOfMergeTreeTables") // { width = 3 }
                , (P.statWithThreshold "Active parts" (S.statGauge "ClickHouseMetrics_PartsActive") { mode = "absolute", steps = [ { color = "green", value = None Natural }, { color = "yellow", value = Some 200 }, { color = "red", value = Some 500 } ] }) // { width = 3 }
                , (P.statWithThreshold "Max parts/partition" (S.statGauge "ClickHouseAsyncMetrics_MaxPartCountForPartition") { mode = "absolute", steps = [ { color = "green", value = None Natural }, { color = "yellow", value = Some 100 }, { color = "red", value = Some 300 } ] }) // { width = 3 }
                , (P.stat "Memory tracked" (S.statGauge "ClickHouseMetrics_MemoryTracking")) // { width = 3, unit = T.Unit.Bytes }
                , (P.statWithThreshold "Delayed inserts" (S.statGauge "ClickHouseMetrics_DelayedInserts") T.thresholdErrors) // { width = 3 }
                ]
            }
          , T.Row::{
            , title = "Query Throughput"
            , panels =
                [ (P.timeseries "Queries running" T.Unit.Short (chGauge "ClickHouseMetrics_Query")) // { width = 8 }
                , (P.timeseries "SELECT queries/sec" T.Unit.QueriesPerSec (chRate "ClickHouseProfileEvents_SelectQuery")) // { width = 8 }
                , (P.timeseries "INSERT queries/sec" T.Unit.QueriesPerSec (chRate "ClickHouseProfileEvents_InsertQuery")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Insert Throughput"
            , panels =
                [ (P.timeseries "Inserted rows/sec" T.Unit.RowsPerSec (chRate "ClickHouseProfileEvents_InsertedRows")) // { width = 8 }
                , (P.timeseries "Inserted bytes/sec" T.Unit.BytesPerSec (chRate "ClickHouseProfileEvents_InsertedBytes")) // { width = 8 }
                , (P.timeseries "Failed queries (select + insert)" T.Unit.Short
                    (chGaugeMulti "'ClickHouseProfileEvents_FailedSelectQuery', 'ClickHouseProfileEvents_FailedInsertQuery'")
                  ) // { width = 8, thresholds = Some T.thresholdErrors }
                ]
            }
          , T.Row::{
            , title = "Memory"
            , panels =
                [ (P.timeseries "Memory tracked" T.Unit.Bytes (chGauge "ClickHouseMetrics_MemoryTracking")) // { width = 8 }
                , (P.timeseries "jemalloc resident vs allocated" T.Unit.Bytes
                    (chGaugeMulti "'ClickHouseAsyncMetrics_jemalloc_resident', 'ClickHouseAsyncMetrics_jemalloc_allocated'")
                  ) // { width = 8 }
                , (P.timeseries "OS memory free (without cached)" T.Unit.Bytes (chGauge "ClickHouseAsyncMetrics_OSMemoryFreeWithoutCached")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Merges & Mutations"
            , panels =
                [ (P.timeseries "Background merges" T.Unit.Short (chGauge "ClickHouseMetrics_Merge")) // { width = 8 }
                , (P.timeseries "Merged rows/sec" T.Unit.RowsPerSec (chRate "ClickHouseProfileEvents_MergedRows")) // { width = 8 }
                , (P.timeseries "Merge time (ms/interval)" T.Unit.Milliseconds (chRate "ClickHouseProfileEvents_MergeTotalMilliseconds")) // { width = 8 }
                , P.timeseries "Parts: active vs outdated" T.Unit.Short
                    (chGaugeMulti "'ClickHouseMetrics_PartsActive', 'ClickHouseMetrics_PartsOutdated'")
                , (P.timeseries "Max parts per partition" T.Unit.Short (chGauge "ClickHouseAsyncMetrics_MaxPartCountForPartition"))
                    // { thresholds = Some { mode = "absolute", steps = [ { color = "green", value = None Natural }, { color = "yellow", value = Some 100 }, { color = "red", value = Some 300 } ] } }
                ]
            }
          , T.Row::{
            , title = "Storage (MergeTree)"
            , panels =
                [ (P.timeseries "Total compressed size" T.Unit.Bytes (chGauge "ClickHouseAsyncMetrics_TotalBytesOfMergeTreeTables")) // { width = 8 }
                , (P.timeseries "Total rows stored" T.Unit.Short (chGauge "ClickHouseAsyncMetrics_TotalRowsOfMergeTreeTables")) // { width = 8 }
                , (P.timeseries "Tables / databases" T.Unit.Short (chGaugeMulti "'ClickHouseAsyncMetrics_NumberOfTables', 'ClickHouseAsyncMetrics_NumberOfDatabases'")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "S3 / R2 (Object Storage)"
            , panels =
                [ (P.timeseries "S3 read bytes/sec" T.Unit.BytesPerSec (chRate "ClickHouseProfileEvents_ReadBufferFromS3Bytes")) // { width = 6 }
                , (P.timeseries "S3 write bytes/sec" T.Unit.BytesPerSec (chRate "ClickHouseProfileEvents_WriteBufferFromS3Bytes")) // { width = 6 }
                , (P.timeseries "S3 read requests/sec" T.Unit.ReqPerSec (chRate "ClickHouseProfileEvents_S3ReadRequestsCount")) // { width = 6 }
                , (P.timeseries "S3 write requests/sec" T.Unit.ReqPerSec (chRate "ClickHouseProfileEvents_S3WriteRequestsCount")) // { width = 6 }
                ]
            }
          , T.Row::{
            , title = "Disk I/O"
            , panels =
                [ (P.timeseries "Disk read time (ms/interval)" T.Unit.Milliseconds "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM ${S.sum} WHERE MetricName = 'ClickHouseProfileEvents_DiskReadElapsedMicroseconds' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time") // { width = 8 }
                , (P.timeseries "Disk write time (ms/interval)" T.Unit.Milliseconds "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM ${S.sum} WHERE MetricName = 'ClickHouseProfileEvents_DiskWriteElapsedMicroseconds' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time") // { width = 8 }
                , (P.timeseries "Open file descriptors (R/W)" T.Unit.Short (chGaugeMulti "'ClickHouseMetrics_OpenFileForRead', 'ClickHouseMetrics_OpenFileForWrite'")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Connections & Network"
            , panels =
                [ (P.timeseries "Connections by type" T.Unit.Short (chGaugeMulti "'ClickHouseMetrics_TCPConnection', 'ClickHouseMetrics_HTTPConnection', 'ClickHouseMetrics_InterserverConnection'")) // { width = 8 }
                , (P.timeseries "Network send bytes/sec" T.Unit.BytesPerSec (chRate "ClickHouseProfileEvents_NetworkSendBytes")) // { width = 8 }
                , (P.timeseries "Network receive bytes/sec" T.Unit.BytesPerSec (chRate "ClickHouseProfileEvents_NetworkReceiveBytes")) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Replication"
            , panels =
                [ (P.timeseries "Replica fetch / send" T.Unit.Short (chGaugeMulti "'ClickHouseMetrics_ReplicatedFetch', 'ClickHouseMetrics_ReplicatedSend'")) // { width = 8 }
                , (P.timeseries "Max replication queue size" T.Unit.Short (chGauge "ClickHouseAsyncMetrics_ReplicasMaxQueueSize")) // { width = 8 }
                , (P.timeseries "Max replica delay (seconds)" T.Unit.Seconds (chGauge "ClickHouseAsyncMetrics_ReplicasMaxAbsoluteDelay"))
                    // { width = 8, thresholds = Some { mode = "absolute", steps = [ { color = "green", value = None Natural }, { color = "yellow", value = Some 30 }, { color = "red", value = Some 300 } ] } }
                ]
            }
          , T.Row::{
            , title = "Threads & Pools"
            , panels =
                [ (P.timeseries "Global threads (total / active)" T.Unit.Short (chGaugeMulti "'ClickHouseMetrics_GlobalThread', 'ClickHouseMetrics_GlobalThreadActive'")) // { width = 8 }
                , (P.timeseries "Background pool tasks" T.Unit.Short (chGaugeMulti "'ClickHouseMetrics_BackgroundMergesAndMutationsPoolTask', 'ClickHouseMetrics_BackgroundSchedulePoolTask'")) // { width = 8 }
                , (P.timeseries "CPU time (ms/interval)" T.Unit.Milliseconds "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM ${S.sum} WHERE MetricName = 'ClickHouseProfileEvents_OSCPUVirtualTimeMicroseconds' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time") // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "ZooKeeper Client (Server -> Keeper)"
            , panels =
                [ (P.timeseries "ZK in-flight requests" T.Unit.Short (chGauge "ClickHouseMetrics_ZooKeeperRequest")) // { width = 8 }
                , (P.timeseries "ZK watches" T.Unit.Short (chGauge "ClickHouseMetrics_ZooKeeperWatch")) // { width = 8 }
                , (P.timeseries "ZK operations/sec (get/set/create/txn)" T.Unit.OpsPerSec
                    "SELECT time, metric, value FROM (SELECT TimeUnix as time, MetricName as metric, runningDifference(Value) / 30 as value FROM ${S.sum} WHERE MetricName IN ('ClickHouseProfileEvents_ZooKeeperGet', 'ClickHouseProfileEvents_ZooKeeperSet', 'ClickHouseProfileEvents_ZooKeeperCreate', 'ClickHouseProfileEvents_ZooKeeperTransactions') AND ${S.tf} ORDER BY metric, time) WHERE value >= 0 ORDER BY time"
                  ) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Keeper Ensemble (3 nodes)"
            , panels =
                [ (P.timeseries "Keeper sessions by node" T.Unit.Short
                    "SELECT TimeUnix as time, ${S.host} as keeper, avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseMetrics_ZooKeeperSession' AND ${S.host} IN ('ultraviolence', 'guccimane', 'shimmer') AND ${S.tf} GROUP BY time, keeper ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Keeper requests by node" T.Unit.Short
                    "SELECT TimeUnix as time, ${S.host} as keeper, avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseMetrics_ZooKeeperRequest' AND ${S.host} IN ('ultraviolence', 'guccimane', 'shimmer') AND ${S.tf} GROUP BY time, keeper ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Keeper watches by node" T.Unit.Short
                    "SELECT TimeUnix as time, ${S.host} as keeper, avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'ClickHouseMetrics_ZooKeeperWatch' AND ${S.host} IN ('ultraviolence', 'guccimane', 'shimmer') AND ${S.tf} GROUP BY time, keeper ORDER BY time"
                  ) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Compression & IO Wait"
            , panels =
                [ (P.timeseries "Compressed read bytes/sec" T.Unit.BytesPerSec (chRate "ClickHouseProfileEvents_CompressedReadBufferBytes")) // { width = 8 }
                , (P.timeseries "S3 write latency (ms/interval)" T.Unit.Milliseconds "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM ${S.sum} WHERE MetricName = 'ClickHouseProfileEvents_DiskS3WriteMicroseconds' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time") // { width = 8 }
                , (P.timeseries "IO wait time (ms/interval)" T.Unit.Milliseconds "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM ${S.sum} WHERE MetricName = 'ClickHouseProfileEvents_OSIOWaitMicroseconds' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time") // { width = 8 }
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
