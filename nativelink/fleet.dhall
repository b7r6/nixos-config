--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // hypermodern // nativelink // fleet
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  STAGE 1: reproduce the current single-host monolithic config (ultraviolence)
--  from the typed schema, to prove the Dhall layer is sound before changing
--  topology. The sharded multi-arch ring (Stage 2) layers onto this.
let schema = ./schema.dhall

let r = ./render.dhall

let JSON = schema.JSON

let schedulerProps =
      [ { name = "cpu_count", mode = schema.MatchMode.minimum }
      , { name = "memory_kb", mode = schema.MatchMode.minimum }
      , { name = "network_kbps", mode = schema.MatchMode.minimum }
      , { name = "disk_read_iops", mode = schema.MatchMode.minimum }
      , { name = "disk_read_bps", mode = schema.MatchMode.minimum }
      , { name = "disk_write_iops", mode = schema.MatchMode.minimum }
      , { name = "disk_write_bps", mode = schema.MatchMode.minimum }
      , { name = "shm_size", mode = schema.MatchMode.minimum }
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

let storeRoot = "/var/lib/nativelink"

let casMain =
      schema.Store::{
      , name = "CAS_MAIN_STORE"
      , backend =
          r.fastSlow
            (r.filesystem "${storeRoot}/content" "${storeRoot}/tmp" 68719476736)
            ( r.r2
                "6063b6652178f5cf1cfb87e7e41acf1e"
                "straylight-nativelink-cas"
                "cas/"
            )
      }

let acMain =
      schema.Store::{
      , name = "AC_MAIN_STORE"
      , backend =
          r.fastSlow
            (r.memory 67108864)
            ( r.r2
                "6063b6652178f5cf1cfb87e7e41acf1e"
                "straylight-nativelink-cas"
                "ac/"
            )
      }

let workerFastSlow =
      schema.Store::{
      , name = "WORKER_FAST_SLOW_STORE"
      , backend =
          r.fastSlow
            ( r.filesystem
                "${storeRoot}/worker-content"
                "${storeRoot}/worker-tmp"
                68719476736
            )
            (r.ref "CAS_MAIN_STORE")
      }

let publicServer =
      schema.Server::{
      , name = "public"
      , socket_address = "0.0.0.0:50051"
      , tls = Some
        { cert_file = "/var/lib/nativelink-tls/cert.pem"
        , key_file = "/var/lib/nativelink-tls/key.pem"
        }
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

let workerApiServer =
      schema.Server::{
      , name = "private_workers_servers"
      , socket_address = "127.0.0.1:50061"
      , worker_api_scheduler = Some "MAIN_SCHEDULER"
      , admin = True
      , health = True
      }

let localWorker =
      schema.Worker::{
      , worker_api_endpoint = "grpc://127.0.0.1:50061"
      , cas_fast_slow_store = "WORKER_FAST_SLOW_STORE"
      , ac_store = "AC_MAIN_STORE"
      , work_directory = "${storeRoot}/work"
      , platform_properties =
        [ { name = "cpu_arch", values = [ "x86_64" ] }
        , { name = "OSFamily", values = [ "" ] }
        , { name = "container-image", values = [ "" ] }
        , { name = "lre-rs", values = [ "" ] }
        , { name = "ISA", values = [ "x86-64" ] }
        ]
      }

let config =
      schema.Config::{
      , stores = [ casMain, acMain, workerFastSlow ]
      , schedulers =
        [ schema.Scheduler::{
          , name = "MAIN_SCHEDULER"
          , properties = schedulerProps
          }
        ]
      , servers = [ publicServer, workerApiServer ]
      , workers = [ localWorker ]
      }

in  r.renderConfig config
