--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // hypermodern // nativelink // schema
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  TYPED schema for NativeLink's config. NativeLink's JSON is a footgun:
--  `stores`/`schedulers`/`workers`/services are ARRAYS of named objects (not
--  maps — the "invalid type: map, expected a sequence" trap), the store graph is
--  a web of ref_store names, and the property-match modes (exact/minimum/
--  priority) must agree across scheduler/worker/client. This schema makes those
--  Dhall type errors.
--
--  Stores nest arbitrarily (shard→grpc, fast_slow→{filesystem,ref_store},
--  verify→dedup→compression→…) and Dhall has no recursion, so a store's backend
--  is a Prelude JSON value built by the constructors in render.dhall; the
--  ARRAY-of-named-objects invariant (the actual footgun) stays type-enforced
--  here. Shapes validated against the nativelink flake's own
--  nativelink-config/examples/*.json5 + the live ultraviolence config.
let Prelude =
      https://prelude.dhall-lang.org/v23.0.0/package.dhall
        sha256:397ef8d5cf55e576eab4359898f61a4e50058982aaace86268c62418d3027871

let JSON = Prelude.JSON

let MatchMode = < exact | minimum | priority >

let Store =
      { Type =
          { name : Text, backend : List (Prelude.Map.Entry Text JSON.Type) }
      , default = {=}
      }

let PropEntry = { name : Text, mode : MatchMode }

let Scheduler =
      { Type = { name : Text, properties : List PropEntry }, default = {=} }

let CasSvc = { instance_name : Text, cas_store : Text }

let AcSvc = { instance_name : Text, ac_store : Text }

let ExecSvc = { instance_name : Text, cas_store : Text, scheduler : Text }

let CapSvc = { instance_name : Text, scheduler : Text }

let Tls = { cert_file : Text, key_file : Text }

let Server =
      { Type =
          { name : Text
          , socket_address : Text
          , tls : Optional Tls
          , cas : List CasSvc
          , ac : List AcSvc
          , execution : List ExecSvc
          , capabilities : List CapSvc
          , bytestream : List CasSvc
          , worker_api_scheduler : Optional Text
          , admin : Bool
          , health : Bool
          }
      , default =
        { tls = None Tls
        , cas = [] : List CasSvc
        , ac = [] : List AcSvc
        , execution = [] : List ExecSvc
        , capabilities = [] : List CapSvc
        , bytestream = [] : List CasSvc
        , worker_api_scheduler = None Text
        , admin = False
        , health = False
        }
      }

let PlatformProp = { name : Text, values : List Text }

let Worker =
      { Type =
          { worker_api_endpoint : Text
          , cas_fast_slow_store : Text
          , ac_store : Text
          , work_directory : Text
          , entrypoint : Optional Text
          , platform_properties : List PlatformProp
          }
      , default =
        { entrypoint = None Text, platform_properties = [] : List PlatformProp }
      }

let Config =
      { Type =
          { stores : List Store.Type
          , schedulers : List Scheduler.Type
          , servers : List Server.Type
          , workers : List Worker.Type
          , max_open_files : Natural
          }
      , default =
        { schedulers = [] : List Scheduler.Type
        , servers = [] : List Server.Type
        , workers = [] : List Worker.Type
        , max_open_files = 24576
        }
      }

in  { Prelude
    , JSON
    , MatchMode
    , Store
    , PropEntry
    , Scheduler
    , CasSvc
    , AcSvc
    , ExecSvc
    , CapSvc
    , Tls
    , Server
    , PlatformProp
    , Worker
    , Config
    }
