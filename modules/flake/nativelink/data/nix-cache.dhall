--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                  // hypermodern // nativelink // nix-cache
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
let schema = ./schema.dhall

let r = ./render.dhall

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
                r.filesystem "${p.stateDir}/${sub}/content" "${p.stateDir}/${sub}/tmp" cap

        -- NAR blobs: R2-backed fast_slow when R2 is set (bounded local fast tier
        -- fronting the durable bucket, key_prefix nix-nar/), else a local fs CAS.
        let narBackend =
              merge
                { None = fsStore "nar" p.maxNarBytes
                , Some =
                    \(x : R2) ->
                      r.fastSlow (fsStore "nar" p.fastBytes) (r.r2 x.account x.bucket "nix-nar/")
                }
                p.r2

        let baseStores =
              [ schema.Store::{ name = "NIX_NAR_STORE", backend = r.verify narBackend }
              , schema.Store::{
                , name = "NIX_PATH_INFO_STORE"
                , backend = r.completeness (fsStore "path-info" 1073741824) "NIX_NAR_STORE"
                }
              , schema.Store::{ name = "NIX_ALIAS_STORE", backend = fsStore "alias" 1073741824 }
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
