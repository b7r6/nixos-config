--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                           // hypermodern // nativelink // fleet
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  The fleet topology, typed. Emits a per-HOST NativeLink config (scheduler vs
--  worker vs CAS differ per role). See
--  docs/src/infrastructure/nativelink-production.md.
--
--  Topology, two SITES (a site = one scheduler + one CAS shard ring; sites do
--  not dial each other):
--    sju1  shannon (x86_64): scheduler + CAS shard + worker  (laptop, LARP-RBE)
--          R2 slow tier. The old roster (watchtower/guccimane/ultraviolence/
--          weyl) was wiped and sold 2026-10-07 — docs/salvage-checklist-2026-10.md.
--    az    nl-az-{a,b,c} (x86_64, Azure westus2): a = scheduler; all three CAS
--          shard + worker. Azure Blob slow tier (SAS URL from the service env).
--          The soak fleet — docs/azure-soak-fleet.md. Names are MagicDNS: the
--          VMs run no CoreDNS and the registry has no entries for them yet.
--  CAS = a weighted shard ring over each site's CAS servers (grpc), hashed by
--  digest; each node fronts a local NVMe fast tier over the site's shared slow
--  tier, which is the durable truth.
let schema = ./schema.dhall

let r = ./render.dhall

let Prelude = schema.Prelude

let List/map = Prelude.List.map

let List/filter = Prelude.List.filter

let storeRoot = "/var/lib/nativelink"

let r2Account = "6063b6652178f5cf1cfb87e7e41acf1e"

let r2Bucket = "straylight-nativelink-cas"

let Arch = < x86_64 | aarch64 >

let Site = < sju1 | az | sk1 >

let SlowTier = < r2 | azure >

--  How a host's roles map onto processes. `monolithic`: one nativelink runs
--  every role the host has (configFor). `split`: one process per role —
--  scheduler (public :50051 + worker_api :50061), cas (:50052), worker (no
--  listener) — cut along the seams the roles already talk over (gRPC to the
--  CAS port, the worker API), so ports, data dirs and hops are the monolith's.
let Layout = < monolithic | split >

let Process = { name : Text, config : schema.Config.Type }

let HostDef =
      { Type =
          { name : Text
          , fqdn : Text
          , arch : Arch
          , site : Site
          , slowTier : SlowTier
          , casWeight : Natural
          , casFastBytes : Natural
          , isScheduler : Bool
          , enabled : Bool
          , maxInflightTasks : Optional Natural
          , layout : Layout
          }
      , default =
        { site = Site.sju1
        , slowTier = SlowTier.r2
        , isScheduler = False
        , enabled = True
        , maxInflightTasks = None Natural
        , layout = Layout.monolithic
        }
      }

let casPort = "50052"

let pushToR2 = False

let casBackend =
      \(fast : r.Backend) ->
      \(slow : r.Backend) ->
        if    pushToR2
        then  r.fastSlowWriteBack fast slow
        else  r.fastSlowReadSlow fast slow

let acBackend =
      \(fast : r.Backend) ->
      \(slow : r.Backend) ->
        if pushToR2 then r.fastSlow fast slow else r.fastSlowReadSlow fast slow

let workerApiPort = "50061"

let publicPort = "50051"

let casRpcTimeoutS = 60

-- The az site's OWN tailnet (deus-ex-b7r6, 2026-10-14) — not the sju1 fleet's.
let azTailnet = "tail8ec1af.ts.net"

let azHost =
      \(n : Text) ->
        HostDef::{
        , name = n
        , fqdn = "${n}.${azTailnet}"
        , arch = Arch.x86_64
        , site = Site.az
        , slowTier = SlowTier.azure
        , casWeight = 4
        , casFastBytes = 107374182400
        , maxInflightTasks = Some 8
        }

let hosts =
      [ HostDef::{
        , name = "shannon"
        , fqdn = "shannon.sju1.s4.gl"
        , arch = Arch.x86_64
        , casWeight = 1
        , casFastBytes = 17179869184
        , isScheduler = True
        , maxInflightTasks = Some 12
        }
      , (azHost "nl-az-a") // { isScheduler = True }
      , azHost "nl-az-b"
      , azHost "nl-az-c"
      , -- sk1: railgun, the Azure (Sweden Central) dev box — a one-host site
        -- like shannon's: scheduler + the only CAS shard + worker, R2 slow tier.
        -- 64 vCPU / 256 GiB / 1 TiB: a 200 GiB CAS fast tier beside the nix
        -- cache's 256 GiB. The fqdn is pinned to loopback on the host itself
        -- (configurations/nixos/railgun) until the sk1 zone is served. Split:
        -- the box also runs Forgejo, Kanidm, ClickHouse and Postgres, so a
        -- worker crash must not take the CAS and the queue down with it.
        HostDef::{
        , name = "railgun"
        , fqdn = "railgun.sk1.s4.gl"
        , arch = Arch.x86_64
        , site = Site.sk1
        , casWeight = 1
        , casFastBytes = 214748364800
        , isScheduler = True
        , maxInflightTasks = Some 48
        , layout = Layout.split
        }
      ]

let archCpu = \(a : Arch) -> merge { x86_64 = "x86_64", aarch64 = "aarch64" } a

let archISA = \(a : Arch) -> merge { x86_64 = "x86-64", aarch64 = "aarch64" } a

let siteId = \(s : Site) -> merge { sju1 = 0, az = 1, sk1 = 2 } s

let sameSite =
      \(a : HostDef.Type) ->
      \(b : HostDef.Type) ->
        Prelude.Natural.equal (siteId a.site) (siteId b.site)

let enabledHosts =
      List/filter HostDef.Type (\(h : HostDef.Type) -> h.enabled) hosts

--  The hosts that share h's site (its CAS ring + its scheduler's workers).
let siteHosts =
      \(h : HostDef.Type) ->
        List/filter HostDef.Type (\(x : HostDef.Type) -> sameSite h x) enabledHosts

let schedulerFqdnFor =
      \(h : HostDef.Type) ->
        merge
          { None = h.fqdn, Some = \(s : HostDef.Type) -> s.fqdn }
          ( Prelude.List.head
              HostDef.Type
              ( List/filter
                  HostDef.Type
                  (\(x : HostDef.Type) -> x.isScheduler)
                  (siteHosts h)
              )
          )

--  The site's durable slow tier, per store prefix.
let slowStore =
      \(h : HostDef.Type) ->
      \(prefix : Text) ->
        merge
          { r2 = r.r2 r2Account r2Bucket prefix, azure = r.azure prefix }
          h.slowTier

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
                -- pushToR2: write-back, so buck2 CAS uploads return at NVMe
                -- speed and R2 fills in the background (nativelink #35).
                casBackend
                  ( r.cacheMetrics
                      "cas-fast"
                      ( r.filesystem
                          "${storeRoot}/content"
                          "${storeRoot}/tmp"
                          h.casFastBytes
                      )
                  )
                  (r.cacheMetrics "cas-slow" (slowStore h "cas/"))
            }
          , schema.Store::{
            , name = "AC_LOCAL"
            , backend =
                acBackend
                  (r.cacheMetrics "ac-fast" (r.memory 67108864))
                  (r.cacheMetrics "ac-slow" (slowStore h "ac/"))
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

let mkShardRing =
      \(svc : Text) ->
      \(timeoutS : Natural) ->
      \(ring : List HostDef.Type) ->
        r.shard
          ( List/map
              HostDef.Type
              r.ShardEntry
              ( \(h : HostDef.Type) ->
                  { store =
                      r.grpc "main" "grpc://${h.fqdn}:${casPort}" svc timeoutS
                  , weight = h.casWeight
                  }
              )
              ring
          )

let casShardRing = \(h : HostDef.Type) -> mkShardRing "cas" casRpcTimeoutS (siteHosts h)

let casShardRingBulk =
      \(h : HostDef.Type) -> mkShardRing "cas" casBulkRpcTimeoutS (siteHosts h)

let acShardRing = \(h : HostDef.Type) -> mkShardRing "ac" casRpcTimeoutS (siteHosts h)

let schedulerConfig =
      \(h : HostDef.Type) ->
        schema.Config::{
        , stores =
          [ schema.Store::{
            , name = "CAS_MAIN_STORE"
            , backend = r.cacheMetrics "cas-main" (casShardRing h)
            }
          , schema.Store::{
            , name = "AC_MAIN_STORE"
            , backend = r.cacheMetrics "ac-main" (acShardRing h)
            }
          , schema.Store::{
            , name = "CAS_MAIN_STORE_BULK"
            , backend = casShardRingBulk h
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
              -- pull straight against the CAS at http://<scheduler>:50051/v2/.
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
          [ schema.Store::{ name = "REMOTE_CAS", backend = casShardRing h }
          , schema.Store::{ name = "REMOTE_AC", backend = acShardRing h }
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
            , worker_api_endpoint =
                "grpc://${schedulerFqdnFor h}:${workerApiPort}"
            , cas_fast_slow_store = "WORKER_FAST_SLOW_STORE"
            , ac_store = "REMOTE_AC"
            , work_directory = "${storeRoot}/work"
            , max_inflight_tasks = h.maxInflightTasks
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
            then  mergeConfigs (schedulerConfig h) casPlusWorker
            else  casPlusWorker

--  The processes a host runs. A monolithic host's single process is configFor,
--  exactly what render-all.dhall hands the fork's module.
let processesFor =
      \(h : HostDef.Type) ->
        merge
          { monolithic = [ { name = "nativelink", config = configFor h } ]
          , split =
                ( if    h.isScheduler
                  then  [ { name = "scheduler", config = schedulerConfig h } ]
                  else  [] : List Process
                )
              # [ { name = "cas", config = casServerConfig h }
                , { name = "worker", config = workerConfig h }
                ]
          }
          h.layout

in  { hosts
    , enabledHosts
    , HostDef
    , Layout
    , Process
    , configFor
    , processesFor
    , renderFor = \(h : HostDef.Type) -> r.renderConfig (configFor h)
    , renderProcessesFor =
        \(h : HostDef.Type) ->
          List/map
            Process
            { process : Text, json : Text }
            ( \(p : Process) ->
                { process = p.name, json = r.renderConfig p.config }
            )
            (processesFor h)
    }
