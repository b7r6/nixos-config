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

-- Per-RPC deadline for every shard-ring grpc peer. 60s is generous for
-- LAN-NVMe unary calls and ByteStream writes (multi-hundred-MB toolchain
-- layers included) but bounds the half-open-peer case: a peer that accepts
-- TCP but never answers (wedged/restarting nativelink) times out + retries
-- instead of hanging every CAS RPC on the frontend.
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
      -- guccimane: back in the ring (2026-07-25) after a stand-up. While it was
      -- out, the shared R2 bucket (straylight-nativelink-cas, cas/ prefix) held
      -- the authoritative blobs, so re-adding it just re-warms its shard from R2.
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
      -- weyl: fourth CAS node for redundancy (2026-07-25). casWeight 2 / 32 GiB
      -- fast tier keeps the fleet's weight×16GiB convention (30 GiB RAM, ~1 TB
      -- disk). More shards = more places a blob survives a node loss.
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

-- Bulk-transfer deadline for the shard-ring stores that carry whole OCI
-- layer blobs (the CAS registry ingest and the oci://self projection
-- reads). GrpcStore applies rpc_timeout_s to an ENTIRE streaming write,
-- so the deadline caps blob size at (timeout x ring throughput): the
-- 60s hot-path bound rejects any layer past ~2 GiB at LAN speed (the
-- cuda cell's 2.69 GB layer, found during PROD-3 phase 2). 900s admits
-- multi-GB layers at a 3 MB/s floor while still bounding a wedged peer.
-- The REAL fix is an idle-based (progress-resetting) deadline in
-- GrpcStore's streaming RPCs — see UPSTREAM-LEDGER in the fork.
let casBulkRpcTimeoutS = 900

let mkCasShardRing =
      \(timeoutS : Natural) ->
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
                        timeoutS
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
        , -- The bulk-deadline view of the SAME CAS ring, for whole-layer
          -- blob transfers (see casBulkRpcTimeoutS above). Same members,
          -- same weights, same bytes — only the per-RPC deadline differs.
          schema.Store::{
          , name = "CAS_MAIN_STORE_BULK"
          , backend = casShardRingBulk
          }
        , -- OCI registry digest-alias index (PROD-3): string-keyed
          -- `oci-digest:sha256:<hex>` -> canonical-identity records, behind
          -- completeness_checking against the CAS ring so an alias whose
          -- blob was evicted 404s instead of advertising it. Records are
          -- content-derived and rebuildable by re-pushing images, so a
          -- local filesystem store (no R2 tier) is acceptable durability.
          schema.Store::{
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
        , -- OCI registry tag refs: MUTABLE string-keyed records. Plain
          -- filesystem — never existence_cache (drops overwrites), never
          -- verify/size_partitioning (string keys).
          schema.Store::{
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
                  cas_store = Some "CAS_MAIN_STORE_BULK"
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
          [ schema.Store::{
            , name = "REMOTE_CAS"
            -- The worker reads through its own view of the SHARD RING (dialing
            -- owner nodes' :50052 directly), NOT its own node's CAS. With the
            -- write-back CAS_LOCAL, a fresh buck2 upload lives on the ring
            -- owner's NVMe synchronously while the shared-R2 copy is still in
            -- flight — an own-node read misses both tiers ("Missing CAS inputs
            -- during prepare_action", FAILED_PRECONDITION) until R2 lands. The
            -- ring view makes worker reads owner-NVMe-consistent; R2 stays the
            -- durability floor, not a read dependency.
            , backend = casShardRing
            }
          , schema.Store::{
            , name = "REMOTE_AC"
            -- Same consistency argument for action results.
            , backend = acShardRing
            }
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
