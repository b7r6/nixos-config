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
        , name = "shimmer"
        , fqdn = "shimmer.sju1.s4.gl"
        , arch = Arch.aarch64
        , casWeight = 2
        , casFastBytes = 34359738368
        , enabled = False
        }
      , HostDef::{
        , name = "ultraviolence"
        , fqdn = "ultraviolence.sju1.s4.gl"
        , arch = Arch.x86_64
        , casWeight = 1
        , casFastBytes = 17179869184
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
                r.fastSlow
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
                r.fastSlow (r.memory 67108864) (r.r2 r2Account r2Bucket "ac/")
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
            }
          ]
        }

let casShardRing =
      r.shard
        ( List/map
            HostDef.Type
            r.ShardEntry
            ( \(h : HostDef.Type) ->
                { store = r.grpc "main" "grpc://${h.fqdn}:${casPort}" "cas"
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
                { store = r.grpc "main" "grpc://${h.fqdn}:${casPort}" "ac"
                , weight = h.casWeight
                }
            )
            enabledHosts
        )

let schedulerConfig =
      schema.Config::{
      , stores =
        [ schema.Store::{ name = "CAS_MAIN_STORE", backend = casShardRing }
        , schema.Store::{ name = "AC_MAIN_STORE", backend = acShardRing }
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
            , backend = r.grpc "main" "grpc://${h.fqdn}:${casPort}" "cas"
            }
          , schema.Store::{
            , name = "REMOTE_AC"
            , backend = r.grpc "main" "grpc://${h.fqdn}:${casPort}" "ac"
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
