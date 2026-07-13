-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                // hypermodern // grafana // clickhouse-internals
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- the OLAP engine that stores our telemetry. watch it watch itself.
let T = ../schema/types.dhall

let S = ../schema/sql.dhall

let Q = ../schema/queries.dhall

let P = ../schema/panels.dhall

let R = ../schema/render.dhall

let m = "ClickHouseMetrics_"

let e = "ClickHouseProfileEvents_"

let a = "ClickHouseAsyncMetrics_"

let usRate =
      \(metric : Text) ->
        "SELECT TimeUnix as time, runningDifference(Value) / 1000 as value FROM ${S.sum} WHERE MetricName = '${metric}' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"

let ensemble =
      "${S.host} IN (SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE MetricName LIKE '${a}Keeper%' AND TimeUnix > now() - INTERVAL 5 MINUTE)"

let thresholdParts =
      { mode = "absolute"
      , steps =
        [ { color = "green", value = None Natural }
        , { color = "yellow", value = Some 200 }
        , { color = "red", value = Some 500 }
        ]
      }

let thresholdMaxParts =
      { mode = "absolute"
      , steps =
        [ { color = "green", value = None Natural }
        , { color = "yellow", value = Some 100 }
        , { color = "red", value = Some 300 }
        ]
      }

let thresholdDelay =
      { mode = "absolute"
      , steps =
        [ { color = "green", value = None Natural }
        , { color = "yellow", value = Some 30 }
        , { color = "red", value = Some 300 }
        ]
      }

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
            [ P.statGauge "Active queries" "${m}Query" // { width = 3 }
            ,     P.stat "Uptime" (Q.statGauge "${a}Uptime")
              //  { width = 3, unit = T.Unit.Seconds }
            ,     P.stat
                    "MergeTree size"
                    (Q.statGauge "${a}TotalBytesOfMergeTreeTables")
              //  { width = 3, unit = T.Unit.Bytes }
            ,     P.statGauge "Total rows" "${a}TotalRowsOfMergeTreeTables"
              //  { width = 3 }
            ,     P.statWithThreshold
                    "Active parts"
                    (Q.statGauge "${m}PartsActive")
                    thresholdParts
              //  { width = 3 }
            ,     P.statWithThreshold
                    "Max parts/partition"
                    (Q.statGauge "${a}MaxPartCountForPartition")
                    thresholdMaxParts
              //  { width = 3 }
            ,     P.stat "Memory tracked" (Q.statGauge "${m}MemoryTracking")
              //  { width = 3, unit = T.Unit.Bytes }
            ,     P.statWithThreshold
                    "Delayed inserts"
                    (Q.statGauge "${m}DelayedInserts")
                    T.thresholdErrors
              //  { width = 3 }
            ]
          }
        , T.Row::{
          , title = "Query Throughput"
          , panels =
            [     P.timeseries
                    "Queries running"
                    T.Unit.Short
                    (Q.gaugeSingle "${m}Query")
              //  { width = 8 }
            ,     P.timeseries
                    "SELECT/sec"
                    T.Unit.QueriesPerSec
                    (Q.rate "${e}SelectQuery")
              //  { width = 8 }
            ,     P.timeseries
                    "INSERT/sec"
                    T.Unit.QueriesPerSec
                    (Q.rate "${e}InsertQuery")
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "Insert Throughput"
          , panels =
            [     P.timeseries
                    "Rows/sec"
                    T.Unit.RowsPerSec
                    (Q.rate "${e}InsertedRows")
              //  { width = 8 }
            ,     P.timeseries
                    "Bytes/sec"
                    T.Unit.BytesPerSec
                    (Q.rate "${e}InsertedBytes")
              //  { width = 8 }
            ,     P.timeseries
                    "Failed queries"
                    T.Unit.Short
                    ( Q.gaugeMulti
                        "'${e}FailedSelectQuery', '${e}FailedInsertQuery'"
                    )
              //  { width = 8, thresholds = Some T.thresholdErrors }
            ]
          }
        , T.Row::{
          , title = "Memory"
          , panels =
            [     P.timeseries
                    "Memory tracked"
                    T.Unit.Bytes
                    (Q.gaugeSingle "${m}MemoryTracking")
              //  { width = 8 }
            ,     P.timeseries
                    "jemalloc resident vs allocated"
                    T.Unit.Bytes
                    ( Q.gaugeMulti
                        "'${a}jemalloc_resident', '${a}jemalloc_allocated'"
                    )
              //  { width = 8, description = "gap = fragmentation" }
            ,     P.timeseries
                    "OS free (no cache)"
                    T.Unit.Bytes
                    (Q.gaugeSingle "${a}OSMemoryFreeWithoutCached")
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "Merges & Mutations"
          , panels =
            [     P.timeseries
                    "Background merges"
                    T.Unit.Short
                    (Q.gaugeSingle "${m}Merge")
              //  { width = 8 }
            ,     P.timeseries
                    "Merged rows/sec"
                    T.Unit.RowsPerSec
                    (Q.rate "${e}MergedRows")
              //  { width = 8 }
            ,     P.timeseries
                    "Merge time"
                    T.Unit.Milliseconds
                    (Q.rate "${e}MergeTotalMilliseconds")
              //  { width = 8 }
            , P.timeseries
                "Parts: active vs outdated"
                T.Unit.Short
                (Q.gaugeMulti "'${m}PartsActive', '${m}PartsOutdated'")
            ,     P.timeseries
                    "Max parts/partition"
                    T.Unit.Short
                    (Q.gaugeSingle "${a}MaxPartCountForPartition")
              //  { thresholds = Some thresholdMaxParts
                  , description = ">300 triggers InsertDelay"
                  }
            ]
          }
        , T.Row::{
          , title = "Storage"
          , panels =
            [     P.timeseries
                    "Total size"
                    T.Unit.Bytes
                    (Q.gaugeSingle "${a}TotalBytesOfMergeTreeTables")
              //  { width = 8 }
            ,     P.timeseries
                    "Total rows"
                    T.Unit.Short
                    (Q.gaugeSingle "${a}TotalRowsOfMergeTreeTables")
              //  { width = 8 }
            ,     P.timeseries
                    "Tables / databases"
                    T.Unit.Short
                    ( Q.gaugeMulti
                        "'${a}NumberOfTables', '${a}NumberOfDatabases'"
                    )
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "S3 / R2"
          , panels =
            [     P.timeseries
                    "Read bytes/sec"
                    T.Unit.BytesPerSec
                    (Q.rate "${e}ReadBufferFromS3Bytes")
              //  { width = 6 }
            ,     P.timeseries
                    "Write bytes/sec"
                    T.Unit.BytesPerSec
                    (Q.rate "${e}WriteBufferFromS3Bytes")
              //  { width = 6 }
            ,     P.timeseries
                    "Read reqs/sec"
                    T.Unit.ReqPerSec
                    (Q.rate "${e}S3ReadRequestsCount")
              //  { width = 6 }
            ,     P.timeseries
                    "Write reqs/sec"
                    T.Unit.ReqPerSec
                    (Q.rate "${e}S3WriteRequestsCount")
              //  { width = 6 }
            ]
          }
        , T.Row::{
          , title = "Disk I/O"
          , panels =
            [     P.timeseries
                    "Read time"
                    T.Unit.Milliseconds
                    (usRate "${e}DiskReadElapsedMicroseconds")
              //  { width = 8 }
            ,     P.timeseries
                    "Write time"
                    T.Unit.Milliseconds
                    (usRate "${e}DiskWriteElapsedMicroseconds")
              //  { width = 8 }
            ,     P.timeseries
                    "Open FDs (R/W)"
                    T.Unit.Short
                    ( Q.gaugeMulti
                        "'${m}OpenFileForRead', '${m}OpenFileForWrite'"
                    )
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "Connections & Network"
          , panels =
            [     P.timeseries
                    "By type"
                    T.Unit.Short
                    ( Q.gaugeMulti
                        "'${m}TCPConnection', '${m}HTTPConnection', '${m}InterserverConnection'"
                    )
              //  { width = 8 }
            ,     P.timeseries
                    "Net send/sec"
                    T.Unit.BytesPerSec
                    (Q.rate "${e}NetworkSendBytes")
              //  { width = 8 }
            ,     P.timeseries
                    "Net recv/sec"
                    T.Unit.BytesPerSec
                    (Q.rate "${e}NetworkReceiveBytes")
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "Replication"
          , panels =
            [     P.timeseries
                    "Fetch / Send"
                    T.Unit.Short
                    (Q.gaugeMulti "'${m}ReplicatedFetch', '${m}ReplicatedSend'")
              //  { width = 8 }
            ,     P.timeseries
                    "Max queue"
                    T.Unit.Short
                    (Q.gaugeSingle "${a}ReplicasMaxQueueSize")
              //  { width = 8 }
            ,     P.timeseries
                    "Max delay"
                    T.Unit.Seconds
                    (Q.gaugeSingle "${a}ReplicasMaxAbsoluteDelay")
              //  { width = 8, thresholds = Some thresholdDelay }
            ]
          }
        , T.Row::{
          , title = "Threads & Pools"
          , panels =
            [     P.timeseries
                    "Global threads"
                    T.Unit.Short
                    ( Q.gaugeMulti
                        "'${m}GlobalThread', '${m}GlobalThreadActive'"
                    )
              //  { width = 8 }
            ,     P.timeseries
                    "Background pool"
                    T.Unit.Short
                    ( Q.gaugeMulti
                        "'${m}BackgroundMergesAndMutationsPoolTask', '${m}BackgroundSchedulePoolTask'"
                    )
              //  { width = 8 }
            ,     P.timeseries
                    "CPU time"
                    T.Unit.Milliseconds
                    (usRate "${e}OSCPUVirtualTimeMicroseconds")
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "ZooKeeper Client"
          , panels =
            [     P.timeseries
                    "In-flight requests"
                    T.Unit.Short
                    (Q.gaugeSingle "${m}ZooKeeperRequest")
              //  { width = 8 }
            ,     P.timeseries
                    "Watches"
                    T.Unit.Short
                    (Q.gaugeSingle "${m}ZooKeeperWatch")
              //  { width = 8 }
            ,     P.timeseries
                    "Ops/sec (get/set/create/txn)"
                    T.Unit.OpsPerSec
                    (Q.rateByKey "${e}ZooKeeperGet" "MetricName" "metric")
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "Keeper Ensemble"
          , panels =
            [     P.timeseries
                    "Sessions by node"
                    T.Unit.Short
                    (Q.byNodeFiltered "${m}ZooKeeperSession" ensemble "keeper")
              //  { width = 8 }
            ,     P.timeseries
                    "Requests by node"
                    T.Unit.Short
                    (Q.byNodeFiltered "${m}ZooKeeperRequest" ensemble "keeper")
              //  { width = 8 }
            ,     P.timeseries
                    "Watches by node"
                    T.Unit.Short
                    (Q.byNodeFiltered "${m}ZooKeeperWatch" ensemble "keeper")
              //  { width = 8 }
            ]
          }
        , T.Row::{
          , title = "Compression & IO Wait"
          , panels =
            [     P.timeseries
                    "Compressed read/sec"
                    T.Unit.BytesPerSec
                    (Q.rate "${e}CompressedReadBufferBytes")
              //  { width = 8 }
            ,     P.timeseries
                    "S3 write latency"
                    T.Unit.Milliseconds
                    (usRate "${e}DiskS3WriteMicroseconds")
              //  { width = 8 }
            ,     P.timeseries
                    "IO wait"
                    T.Unit.Milliseconds
                    (usRate "${e}OSIOWaitMicroseconds")
              //  { width = 8, description = "high = storage bottleneck" }
            ]
          }
        ]
      }

in  R.renderDashboard dashboard
