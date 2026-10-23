--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                    // hypermodern // nativelink // nix // cache
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  The nix_cache substituter + cas_witness fetch-proxy config, rendered from the
--  SAME typed schema/constructors as the RE fleet (schema.dhall / render.dhall) —
--  so the R2 store shape, fast_slow, verify, etc. are defined exactly once.
--
--  Unlike the RE config (driven by the fleet host-list), the nix_cache runs on
--  every host, so its per-host values come from the NixOS module options: the
--  module writes a `Params` record and applies `render` to it via IFD. Paths and
--  toggles that live in NixOS (state dir, agenix key, which upstreams) are inputs
--  here; the store composition and R2 wiring are shared with the RE side.
--
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
let schema = ./schema.dhall

let r = ./render.dhall

let site = ./nix-cache-site.dhall

let R2 = { account : Text, bucket : Text }

let FetchProxy =
      { listen : Text, maxFetch : Natural, caCert : Text, caKey : Text }

let Params =
      { stateDir : Text
      , storeDir : Text
      , instanceName : Text
      , listen : Text
      , priority : Natural
      , maxNarUpload : Natural
      , maxNarBytes : Natural
      , fastBytes : Natural
      , r2 : Optional R2
      , signingKeyFile : Optional Text
      , upstreams : List schema.UpstreamCache
      , fetchProxy : Optional FetchProxy
      }

let render =
      \(p : Params) ->
        let fsStore =
              \(sub : Text) ->
              \(cap : Natural) ->
                r.filesystem
                  "${p.stateDir}/${sub}/content"
                  "${p.stateDir}/${sub}/tmp"
                  cap

        --  Whether this host PUSHES to R2 (./nix-cache-site.dhall: the one
        --  per-host fact Params cannot carry, overlaid per host by shim.nix).
        --
        --  Consumer (False): R2 is read-only — misses still pull from it and
        --  fill the fast tier, nothing is pushed, and narinfo + alias records
        --  stay local. Every path that lands in /nix/store (substituted from
        --  cache.nixos.org or not) reaches the NAR store via the watcher or
        --  read-through, and mirroring that saturated a laptop uplink: 33
        --  parallel PUTs, RTT 20 → 900 ms, downloads starved to 300 KiB/s
        --  (2026-10-12).
        --
        --  Producer (True, railgun 2026-10-23): R2 is the truth the SITE
        --  shares. NARs write back (the upload returns at local speed, R2
        --  fills behind it); narinfo and alias records write THROUGH, so the
        --  moment a producer answers a PUT the record is in R2 for every other
        --  host — their completeness check against the NAR store (an R2 HEAD
        --  on a cold fast tier) hides the write-back window as a 404, never a
        --  NAR that cannot be served. Both string-keyed stores work on R2
        --  because the fork's object store keys by `key.as_str()`: the records
        --  land under nix-path-info/<nixbase32> and nix-alias/nar-alias:<name>.
        let push = site.pushToR2

        let tiered =
              \(sub : Text) ->
              \(cap : Natural) ->
              \(prefix : Text) ->
              \(writeBack : Bool) ->
                merge
                  { None = fsStore sub cap
                  , Some =
                      \(x : R2) ->
                        let fast = fsStore sub cap

                        let slow = r.r2 x.account x.bucket prefix

                        in  if    push
                            then  ( if    writeBack
                                    then  r.fastSlowWriteBack fast slow
                                    else  r.fastSlow fast slow
                                  )
                            else  r.fastSlowReadSlow fast slow
                  }
                  p.r2

        let narBackend =
              merge
                { None = fsStore "nar" p.maxNarBytes
                , Some =
                    \(_ : R2) -> tiered "nar" p.fastBytes "nix-nar/" True
                }
                p.r2

        --  A consumer keeps its records local (byte-identical to before
        --  2026-10-23); a producer tiers them over R2, write-through.
        let recordBackend =
              \(sub : Text) ->
              \(prefix : Text) ->
                if    push
                then  tiered sub 1073741824 prefix False
                else  fsStore sub 1073741824

        let baseStores =
              [ schema.Store::{
                , name = "NIX_NAR_STORE"
                , backend = r.verify narBackend
                }
              , schema.Store::{
                , name = "NIX_PATH_INFO_STORE"
                , backend =
                    r.completeness
                      (recordBackend "path-info" "nix-path-info/")
                      "NIX_NAR_STORE"
                }
              , schema.Store::{
                , name = "NIX_ALIAS_STORE"
                , backend = recordBackend "alias" "nix-alias/"
                }
              ]

        let proxyStores =
              merge
                { None = [] : List schema.Store.Type
                , Some =
                    \(_ : FetchProxy) ->
                      [ schema.Store::{
                        , name = "FETCH_ALIAS"
                        , backend = fsStore "fetch-alias" 1073741824
                        }
                      ]
                }
                p.fetchProxy

        let nixCacheSvc =
              schema.NixCacheSvc::{
              , instance_name = p.instanceName
              , cas_store = "NIX_NAR_STORE"
              , path_info_store = "NIX_PATH_INFO_STORE"
              , alias_store = "NIX_ALIAS_STORE"
              , store_dir = p.storeDir
              , priority = p.priority
              , max_nar_size_bytes = p.maxNarUpload
              , signing_key_files =
                  merge
                    { None = [] : List Text, Some = \(f : Text) -> [ f ] }
                    p.signingKeyFile
              , upstream_caches = p.upstreams
              }

        let proxyServers =
              merge
                { None = [] : List schema.Server.Type
                , Some =
                    \(fp : FetchProxy) ->
                      [ schema.Server::{
                        , name = "cas-witness"
                        , socket_address = fp.listen
                        , cas_witness = Some
                          { cas_store = "NIX_NAR_STORE"
                          , alias_store = "FETCH_ALIAS"
                          , ca_cert_file = fp.caCert
                          , ca_key_file = fp.caKey
                          , max_fetch_size_bytes = fp.maxFetch
                          }
                        }
                      ]
                }
                p.fetchProxy

        in  r.renderConfig
              schema.Config::{
              , stores = baseStores # proxyStores
              , servers =
                    [ schema.Server::{
                      , name = "nix-cache"
                      , socket_address = p.listen
                      , nix_cache = [ nixCacheSvc ]
                      , health = True
                      }
                    ]
                  # proxyServers
              }

in  { Params, R2, FetchProxy, render }
