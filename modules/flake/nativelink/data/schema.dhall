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

-- Remote Asset FetchDirectory + the OCI→REAPI toolchain bridge. `fetch_store`
-- backs remote-asset lookups; the optional `oci` block turns FetchDirectory
-- (oci://…) into a projection into CAS. `registries` fully specifies each
-- registry (scheme/TLS/creds); an unmatched host is anonymous HTTPS.
let OciRegistry =
      { Type =
          { host : Text
          , scheme : Optional Text
          , root_certificates : Optional Text
          , insecure_skip_verify : Bool
          , username : Optional Text
          , password : Optional Text
          , bearer_token : Optional Text
          }
      , default =
        { scheme = None Text
        , root_certificates = None Text
        , insecure_skip_verify = False
        , username = None Text
        , password = None Text
        , bearer_token = None Text
        }
      }

let OciFetch =
      { Type =
          { cas_store : Optional Text
          , dedup_check : Bool
          , digest_function : Text
          , registries : List OciRegistry.Type
          }
      , default =
        { cas_store = None Text
        , dedup_check = True
        , digest_function = "BLAKE3"
        , registries = [] : List OciRegistry.Type
        }
      }

let FetchSvc =
      { Type =
          { instance_name : Text
          , fetch_store : Text
          , oci : Optional OciFetch.Type
          }
      , default = { oci = None OciFetch.Type }
      }

-- The straylight fork's Nix binary-cache facade + its raw-fetch caching proxy.
-- Not RE services; carried on their own HTTP servers.
let UpstreamCache = { url : Text, trusted_public_keys : List Text }

let NixCacheSvc =
      { Type =
          { instance_name : Text
          , cas_store : Text
          , path_info_store : Text
          , alias_store : Text
          , store_dir : Text
          , priority : Natural
          , max_nar_size_bytes : Natural
          , signing_key_files : List Text
          , upstream_caches : List UpstreamCache
          }
      , default =
        { signing_key_files = [] : List Text
        , upstream_caches = [] : List UpstreamCache
        }
      }

let CasWitnessSvc =
      { cas_store : Text
      , alias_store : Text
      , ca_cert_file : Text
      , ca_key_file : Text
      , max_fetch_size_bytes : Natural
      }

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
          , fetch : List FetchSvc.Type
          , bytestream : List CasSvc
          , worker_api_scheduler : Optional Text
          , nix_cache : List NixCacheSvc.Type
          , cas_witness : Optional CasWitnessSvc
          , admin : Bool
          , health : Bool
          , prometheus : Bool
          }
      , default =
        { tls = None Tls
        , cas = [] : List CasSvc
        , ac = [] : List AcSvc
        , execution = [] : List ExecSvc
        , capabilities = [] : List CapSvc
        , fetch = [] : List FetchSvc.Type
        , bytestream = [] : List CasSvc
        , worker_api_scheduler = None Text
        , nix_cache = [] : List NixCacheSvc.Type
        , cas_witness = None CasWitnessSvc
        , admin = False
        , health = False
        , prometheus = False
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
    , OciRegistry
    , OciFetch
    , FetchSvc
    , UpstreamCache
    , NixCacheSvc
    , CasWitnessSvc
    , Tls
    , Server
    , PlatformProp
    , Worker
    , Config
    }
