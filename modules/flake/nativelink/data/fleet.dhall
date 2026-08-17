--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // hypermodern // nativelink // fleet
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  The fleet topology, typed. Emits a per-HOST NativeLink config (scheduler vs
--  worker vs CAS differ per role). See
--  docs/src/infrastructure/nativelink-production.md.
--
--  Topology (single-site sju1, multi-arch):
--    watchtower (x86_64): scheduler + CAS shard + worker
--    guccimane  (x86_64): CAS shard + worker
--    shimmer    (aarch64): CAS shard + worker  (only aarch64 executor)
--    ultraviolence (x86_64): CAS shard (small) + worker
--  CAS = a weighted shard ring over each node's CAS server (grpc), hashed by
--  digest; each node fronts a local NVMe fast tier over the shared R2 slow tier.
let schema = ./schema.dhall

let r = ./render.dhall

let Prelude = schema.Prelude

let List/map = Prelude.List.map

let storeRoot = "/var/lib/nativelink"

let r2Account = "6063b6652178f5cf1cfb87e7e41acf1e"

let r2Bucket = "straylight-nativelink-cas"

let Arch = < x86_64 | aarch64 >

let HostDef =
      { Type =
          { name : Text
          , fqdn : Text
          , arch : Arch
          , casWeight : Natural
          , casFastBytes : Natural
          , isScheduler : Bool
          , enabled : Bool
          }
      , default = { isScheduler = False, enabled = True }
      }

let schedulerFqdn = "watchtower.sju1.s4.gl"

let casPort = "50052"

let workerApiPort = "50061"

let publicPort = "50051"

let casRpcTimeoutS = 60

let hosts =
      [ HostDef::{
        , name = "watchtower"
        , fqdn = "watchtower.sju1.s4.gl"
        , arch = Arch.x86_64
        , casWeight = 4
        , casFastBytes = 68719476736
        , isScheduler = True
        }
      , HostDef::{
        , name = "guccimane"
        , fqdn = "guccimane.sju1.s4.gl"
        , arch = Arch.x86_64
        , casWeight = 4
        , casFastBytes = 68719476736
        }
      , HostDef::{
        , name = "ultraviolence"
        , fqdn = "ultraviolence.sju1.s4.gl"
        , arch = Arch.x86_64
        , casWeight = 1
        , casFastBytes = 17179869184
        }
      , HostDef::{
        , name = "weyl"
        , fqdn = "weyl.sju1.s4.gl"
        , arch = Arch.x86_64
        , casWeight = 2
        , casFastBytes = 34359738368
        }
      ]

let archCpu = \(a : Arch) -> merge { x86_64 = "x86_64", aarch64 = "aarch64" } a

let archISA = \(a : Arch) -> merge { x86_64 = "x86-64", aarch64 = "aarch64" } a

let enabledHosts =
      Prelude.List.filter HostDef.Type (\(h : HostDef.Type) -> h.enabled) hosts

let schedulerProps =
      [ { name = "cpu_count", mode = schema.MatchMode.minimum }
      , { name = "memory_kb", mode = schema.MatchMode.minimum }
      , { name = "gpu_count", mode = schema.MatchMode.minimum }
      , { name = "gpu_model", mode = schema.MatchMode.exact }
      , { name = "cpu_vendor", mode = schema.MatchMode.exact }
      , { name = "cpu_arch", mode = schema.MatchMode.exact }
      , { name = "cpu_model", mode = schema.MatchMode.exact }
      , { name = "kernel_version", mode = schema.MatchMode.exact }
      , { name = "OSFamily", mode = schema.MatchMode.priority }
      , { name = "container-image", mode = schema.MatchMode.priority }
      , { name = "lre-rs", mode = schema.MatchMode.priority }
      , { name = "ISA", mode = schema.MatchMode.exact }
      ]

let casServerConfig =
      \(h : HostDef.Type) ->
        schema.Config::{
        , stores =
          [ schema.Store::{
            , name = "CAS_LOCAL"
            , backend =
                -- write-back: buck2 CAS uploads return at NVMe speed; R2 is
                -- populated by a background task, so a slow/stalled R2 can no
                -- longer freeze the upload (nativelink #35, fast_slow write-back).
                r.fastSlowWriteBack
                  ( r.cacheMetrics
                      "cas-fast"
                      ( r.filesystem
                          "${storeRoot}/content"
                          "${storeRoot}/tmp"
                          h.casFastBytes
                      )
                  )
                  (r.cacheMetrics "cas-slow" (r.r2 r2Account r2Bucket "cas/"))
            }
          , schema.Store::{
            , name = "AC_LOCAL"
            , backend =
                r.fastSlow
                  (r.cacheMetrics "ac-fast" (r.memory 67108864))
                  (r.cacheMetrics "ac-slow" (r.r2 r2Account r2Bucket "ac/"))
            }
          ]
        , servers =
          [ schema.Server::{
            , name = "cas"
            , socket_address = "0.0.0.0:${casPort}"
            , cas = [ { instance_name = "main", cas_store = "CAS_LOCAL" } ]
            , ac = [ { instance_name = "main", ac_store = "AC_LOCAL" } ]
            , bytestream =
              [ { instance_name = "main", cas_store = "CAS_LOCAL" } ]
            , health = True
            , prometheus = True
            }
          ]
        }

let casBulkRpcTimeoutS = 900

let mkCasShardRing =
      \(timeoutS : Natural) ->
        r.shard
          ( List/map
              HostDef.Type
              r.ShardEntry
              ( \(h : HostDef.Type) ->
                  { store =
                      r.grpc "main" "grpc://${h.fqdn}:${casPort}" "cas" timeoutS
                  , weight = h.casWeight
                  }
              )
              enabledHosts
          )

let casShardRingBulk = mkCasShardRing casBulkRpcTimeoutS

let casShardRing =
      r.shard
        ( List/map
            HostDef.Type
            r.ShardEntry
            ( \(h : HostDef.Type) ->
                { store =
                    r.grpc
                      "main"
                      "grpc://${h.fqdn}:${casPort}"
                      "cas"
                      casRpcTimeoutS
                , weight = h.casWeight
                }
            )
            enabledHosts
        )

let acShardRing =
      r.shard
        ( List/map
            HostDef.Type
            r.ShardEntry
            ( \(h : HostDef.Type) ->
                { store =
                    r.grpc
                      "main"
                      "grpc://${h.fqdn}:${casPort}"
                      "ac"
                      casRpcTimeoutS
                , weight = h.casWeight
                }
            )
            enabledHosts
        )

let schedulerConfig =
      schema.Config::{
      , stores =
        [ schema.Store::{
          , name = "CAS_MAIN_STORE"
          , backend = r.cacheMetrics "cas-main" casShardRing
          }
        , schema.Store::{
          , name = "AC_MAIN_STORE"
          , backend = r.cacheMetrics "ac-main" acShardRing
          }
        , schema.Store::{
          , name = "CAS_MAIN_STORE_BULK"
          , backend = casShardRingBulk
          }
        , schema.Store::{
          , name = "OCI_INDEX_STORE"
          , backend =
              r.completeness
                ( r.filesystem
                    "${storeRoot}/oci-index/content"
                    "${storeRoot}/oci-index/tmp"
                    1073741824
                )
                "CAS_MAIN_STORE"
          }
        , schema.Store::{
          , name = "OCI_REF_STORE"
          , backend =
              r.filesystem
                "${storeRoot}/oci-refs/content"
                "${storeRoot}/oci-refs/tmp"
                1073741824
          }
        ]
      , schedulers =
        [ schema.Scheduler::{
          , name = "MAIN_SCHEDULER"
          , properties = schedulerProps
          }
        ]
      , servers =
        [ schema.Server::{
          , name = "public"
          , socket_address = "0.0.0.0:${publicPort}"
          , cas = [ { instance_name = "main", cas_store = "CAS_MAIN_STORE" } ]
          , ac = [ { instance_name = "main", ac_store = "AC_MAIN_STORE" } ]
          , execution =
            [ { instance_name = "main"
              , cas_store = "CAS_MAIN_STORE"
              , scheduler = "MAIN_SCHEDULER"
              }
            ]
          , bytestream =
            [ { instance_name = "main", cas_store = "CAS_MAIN_STORE" } ]
          , capabilities =
            [ { instance_name = "main", scheduler = "MAIN_SCHEDULER" } ]
          , fetch =
            [ { instance_name = "main"
              , fetch_store = "CAS_MAIN_STORE"
              , oci = Some schema.OciFetch::{
                , -- Bulk deadline for the toolchain-import path: the
                  -- projected-blob uploads AND the dedup has_many (one
                  -- FindMissingBlobs over tens of thousands of digests for
                  -- the ghc/lean/python cells) exceed the 60s hot-path
                  -- ring deadline.
                  cas_store = Some
                    "CAS_MAIN_STORE_BULK"
                , -- dedup_check=false: the import's has_many falls through
                  -- fast_slow to the SLOW tier for every fast-tier miss —
                  -- an R2 existence probe per digest, tens of thousands
                  -- for the ghc/lean/python cells (>900s; observed wedge).
                  -- Unconditional uploads are idempotent and land on the
                  -- write-back NVMe tier at full speed.
                  dedup_check = False
                , registries =
                  [ schema.OciRegistry::{
                    , host = "registry.sju1.s4.gl"
                    , scheme = Some "https"
                    }
                  ]
                , -- oci://self short-circuit: FetchDirectory of images the
                  -- colocated CAS registry holds becomes a local graph walk
                  -- (no network client, nothing fetched twice).
                  self_registry = Some
                  { blob_store = "CAS_MAIN_STORE_BULK"
                  , index_store = "OCI_INDEX_STORE"
                  , ref_store = "OCI_REF_STORE"
                  }
                }
              }
            ]
          , -- The OCI Distribution registry (PROD-3): skopeo/crane push and
            -- pull straight against the CAS at http://watchtower:50051/v2/.
            -- Open-push on this listener matches the existing trust model:
            -- the same tailnet-gated port already accepts arbitrary CAS
            -- writes over gRPC, so a write token would gate nothing an
            -- attacker could not already do. Blobs land in CAS_MAIN_STORE
            -- (the shard ring) under BLAKE3 — ByteStream-readable
            -- fleet-wide, deduped with REAPI blobs post-projection.
            oci_registry =
            [ schema.OciRegistrySvc::{
              , instance_name = "main"
              , cas_store = "CAS_MAIN_STORE_BULK"
              , index_store = "OCI_INDEX_STORE"
              , ref_store = "OCI_REF_STORE"
              , spool_path = "${storeRoot}/oci-spool"
              }
            ]
          , prometheus = True
          }
        , schema.Server::{
          , name = "worker_api"
          , socket_address = "0.0.0.0:${workerApiPort}"
          , worker_api_scheduler = Some "MAIN_SCHEDULER"
          , admin = True
          , health = True
          }
        ]
      }

let workerConfig =
      \(h : HostDef.Type) ->
        schema.Config::{
        , stores =
          [ schema.Store::{ name = "REMOTE_CAS", backend = casShardRing }
          , schema.Store::{ name = "REMOTE_AC", backend = acShardRing }
          , schema.Store::{
            , name = "WORKER_FAST_SLOW_STORE"
            , backend =
                r.fastSlow
                  ( r.filesystem
                      "${storeRoot}/worker-content"
                      "${storeRoot}/worker-tmp"
                      h.casFastBytes
                  )
                  (r.ref "REMOTE_CAS")
            }
          ]
        , workers =
          [ schema.Worker::{
            , worker_api_endpoint = "grpc://${schedulerFqdn}:${workerApiPort}"
            , cas_fast_slow_store = "WORKER_FAST_SLOW_STORE"
            , ac_store = "REMOTE_AC"
            , work_directory = "${storeRoot}/work"
            , platform_properties =
              [ { name = "cpu_arch", values = [ archCpu h.arch ] }
              , { name = "OSFamily", values = [ "linux" ] }
              , { name = "container-image", values = [ "" ] }
              , { name = "lre-rs", values = [ "" ] }
              , { name = "ISA", values = [ archISA h.arch ] }
              ]
            }
          ]
        }

let mergeConfigs =
      \(a : schema.Config.Type) ->
      \(b : schema.Config.Type) ->
        schema.Config::{
        , stores = a.stores # b.stores
        , schedulers = a.schedulers # b.schedulers
        , servers = a.servers # b.servers
        , workers = a.workers # b.workers
        }

let configFor =
      \(h : HostDef.Type) ->
        let casPlusWorker = mergeConfigs (casServerConfig h) (workerConfig h)

        in  if    h.isScheduler
            then  mergeConfigs schedulerConfig casPlusWorker
            else  casPlusWorker

in  { hosts
    , enabledHosts
    , HostDef
    , configFor
    , renderFor = \(h : HostDef.Type) -> r.renderConfig (configFor h)
    }
