--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                      // hypermodern // nativelink // render
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  Store CONSTRUCTORS (so fleet.dhall never hand-writes a backend) + the full
--  Config → NativeLink JSON renderer. Everything is built as Prelude JSON.Type
--  and emitted once, so quoting/escaping/nesting are correct by construction.
let schema = ./schema.dhall

let Prelude = schema.Prelude

let JSON = schema.JSON

let Map/Entry = Prelude.Map.Entry

let List/map = Prelude.List.map

let obj = \(kvs : List (Map/Entry Text JSON.Type)) -> JSON.object kvs

let str = JSON.string

let nat = JSON.natural

let bool = JSON.bool

let arr = JSON.array

let Backend = List (Map/Entry Text JSON.Type)

let wrap = \(b : Backend) -> obj b : JSON.Type

let filesystem =
      \(contentPath : Text) ->
      \(tempPath : Text) ->
      \(maxBytes : Natural) ->
          [ { mapKey = "filesystem"
            , mapValue =
                obj
                  [ { mapKey = "content_path", mapValue = str contentPath }
                  , { mapKey = "temp_path", mapValue = str tempPath }
                  , { mapKey = "eviction_policy"
                    , mapValue =
                        obj
                          [ { mapKey = "max_bytes", mapValue = nat maxBytes } ]
                    }
                  ]
            }
          ]
        : Backend

let memory =
      \(maxBytes : Natural) ->
          [ { mapKey = "memory"
            , mapValue =
                obj
                  [ { mapKey = "eviction_policy"
                    , mapValue =
                        obj
                          [ { mapKey = "max_bytes", mapValue = nat maxBytes } ]
                    }
                  ]
            }
          ]
        : Backend

let grpc =
      \(instanceName : Text) ->
      \(address : Text) ->
      \(storeType : Text) ->
      \(rpcTimeoutS : Natural) ->
          [ { mapKey = "grpc"
            , mapValue =
                obj
                  [ { mapKey = "instance_name", mapValue = str instanceName }
                  , { mapKey = "store_type", mapValue = str storeType }
                  , -- per-RPC deadline (seconds). 0 = disabled (upstream-compat
                    -- default); the fleet SETS it — a half-open peer (host up,
                    -- nativelink wedged/restarting) otherwise queues shard-ring
                    -- RPCs forever and freezes every CAS call on the frontend
                    -- (the watchtower wedge). DeadlineExceeded is retryable, so
                    -- a slow-but-alive peer just retries.
                    { mapKey = "rpc_timeout_s", mapValue = nat rpcTimeoutS }
                  , { mapKey = "endpoints"
                    , mapValue =
                        arr
                          [ obj
                              [ { mapKey = "address", mapValue = str address } ]
                          ]
                    }
                  ]
            }
          ]
        : Backend

let ref =
      \(name : Text) ->
          [ { mapKey = "ref_store"
            , mapValue = obj [ { mapKey = "name", mapValue = str name } ]
            }
          ]
        : Backend

let fastSlowWith =
      \(writeBack : Bool) ->
      \(fast : Backend) ->
      \(slow : Backend) ->
          [ { mapKey = "fast_slow"
            , mapValue =
                obj
                  (     [ { mapKey = "fast", mapValue = wrap fast }
                        , -- write-through: populate the local fast tier on WRITE
                          -- (not just on read). With "get" (write-around) uploaded
                          -- build outputs land in R2 only, so every cache-hit
                          -- read-back paid a ~100ms R2 round-trip instead of a
                          -- local NVMe read. "both" (nativelink's default) makes
                          -- read-back local and fast.
                          { mapKey = "fast_direction", mapValue = str "both" }
                        , { mapKey = "slow", mapValue = wrap slow }
                        ]
                      # ( if    writeBack
                          then  [ -- write-back: the update returns once the fast
                                  -- (NVMe) tier holds the blob; fast->slow (R2) is
                                  -- copied by a background task, so a slow or
                                  -- stalled R2 can no longer backpressure/freeze the
                                  -- client upload. Safe here because shard-ring
                                  -- reads route to the writing node's NVMe; R2 is
                                  -- the async durability / eviction backstop.
                                  { mapKey = "slow_store_write_back"
                                  , mapValue = bool True
                                  }
                                ]
                          else  [] : List (Map/Entry Text JSON.Type)
                        )
                  )
            }
          ]
        : Backend

let fastSlow = fastSlowWith False

let fastSlowWriteBack = fastSlowWith True

let cacheMetrics =
      \(cacheType : Text) ->
      \(inner : Backend) ->
          [ { mapKey = "cache_metrics"
            , mapValue =
                obj
                  [ { mapKey = "cache_type", mapValue = str cacheType }
                  , { mapKey = "backend", mapValue = wrap inner }
                  ]
            }
          ]
        : Backend

let r2 =
      \(accountId : Text) ->
      \(bucket : Text) ->
      \(keyPrefix : Text) ->
          [ { mapKey = "experimental_cloud_object_store"
            , mapValue =
                obj
                  [ { mapKey = "provider", mapValue = str "r2" }
                  , { mapKey = "account_id", mapValue = str accountId }
                  , { mapKey = "bucket", mapValue = str bucket }
                  , { mapKey = "access_key_id"
                    , mapValue = str "\${R2_ACCESS_KEY_ID}"
                    }
                  , { mapKey = "secret_access_key"
                    , mapValue = str "\${R2_SECRET_ACCESS_KEY}"
                    }
                  , { mapKey = "key_prefix", mapValue = str keyPrefix }
                  , { mapKey = "retry"
                    , mapValue =
                        obj
                          [ { mapKey = "max_retries", mapValue = nat 6 }
                          , { mapKey = "delay", mapValue = JSON.double 0.3 }
                          , { mapKey = "jitter", mapValue = JSON.double 0.5 }
                          ]
                    }
                  ]
            }
          ]
        : Backend

let ShardEntry = { store : Backend, weight : Natural }

let shard =
      \(entries : List ShardEntry) ->
          [ { mapKey = "shard"
            , mapValue =
                obj
                  [ { mapKey = "stores"
                    , mapValue =
                        arr
                          ( List/map
                              ShardEntry
                              JSON.Type
                              ( \(e : ShardEntry) ->
                                  obj
                                    [ { mapKey = "store"
                                      , mapValue = wrap e.store
                                      }
                                    , { mapKey = "weight"
                                      , mapValue = nat e.weight
                                      }
                                    ]
                              )
                              entries
                          )
                    }
                  ]
            }
          ]
        : Backend

let verify =
      \(backend : Backend) ->
          [ { mapKey = "verify"
            , mapValue =
                obj
                  [ { mapKey = "verify_size", mapValue = bool True }
                  , { mapKey = "verify_hash", mapValue = bool True }
                  , { mapKey = "backend", mapValue = wrap backend }
                  ]
            }
          ]
        : Backend

let completeness =
      \(backend : Backend) ->
      \(casStore : Text) ->
          [ { mapKey = "completeness_checking"
            , mapValue =
                obj
                  [ { mapKey = "backend", mapValue = wrap backend }
                  , { mapKey = "cas_store", mapValue = wrap (ref casStore) }
                  ]
            }
          ]
        : Backend

let modeText =
      \(m : schema.MatchMode) ->
        merge { exact = "exact", minimum = "minimum", priority = "priority" } m

let storeToJSON =
      \(s : schema.Store.Type) ->
        obj ([ { mapKey = "name", mapValue = str s.name } ] # s.backend)

let schedToJSON =
      \(s : schema.Scheduler.Type) ->
        obj
          [ { mapKey = "name", mapValue = str s.name }
          , { mapKey = "simple"
            , mapValue =
                obj
                  [ { mapKey = "supported_platform_properties"
                    , mapValue =
                        obj
                          ( List/map
                              schema.PropEntry
                              (Map/Entry Text JSON.Type)
                              ( \(p : schema.PropEntry) ->
                                  { mapKey = p.name
                                  , mapValue = str (modeText p.mode)
                                  }
                              )
                              s.properties
                          )
                    }
                  ]
            }
          ]

let casSvcJSON =
      \(x : schema.CasSvc) ->
        obj
          [ { mapKey = "instance_name", mapValue = str x.instance_name }
          , { mapKey = "cas_store", mapValue = str x.cas_store }
          ]

let acSvcJSON =
      \(x : schema.AcSvc) ->
        obj
          [ { mapKey = "instance_name", mapValue = str x.instance_name }
          , { mapKey = "ac_store", mapValue = str x.ac_store }
          ]

let execSvcJSON =
      \(x : schema.ExecSvc) ->
        obj
          [ { mapKey = "instance_name", mapValue = str x.instance_name }
          , { mapKey = "cas_store", mapValue = str x.cas_store }
          , { mapKey = "scheduler", mapValue = str x.scheduler }
          ]

let capSvcJSON =
      \(x : schema.CapSvc) ->
        obj
          [ { mapKey = "instance_name", mapValue = str x.instance_name }
          , { mapKey = "remote_execution"
            , mapValue =
                obj [ { mapKey = "scheduler", mapValue = str x.scheduler } ]
            }
          ]

let upstreamJSON =
      \(u : schema.UpstreamCache) ->
        obj
          [ { mapKey = "url", mapValue = str u.url }
          , { mapKey = "trusted_public_keys"
            , mapValue = arr (List/map Text JSON.Type str u.trusted_public_keys)
            }
          ]

let nixCacheSvcJSON =
      \(x : schema.NixCacheSvc.Type) ->
        obj
          (   [ { mapKey = "instance_name", mapValue = str x.instance_name }
              , { mapKey = "cas_store", mapValue = str x.cas_store }
              , { mapKey = "path_info_store", mapValue = str x.path_info_store }
              , { mapKey = "alias_store", mapValue = str x.alias_store }
              , { mapKey = "store_dir", mapValue = str x.store_dir }
              , { mapKey = "priority", mapValue = nat x.priority }
              , { mapKey = "max_nar_size_bytes"
                , mapValue = nat x.max_nar_size_bytes
                }
              ]
            # ( if    Prelude.List.null Text x.signing_key_files
                then  [] : List (Map/Entry Text JSON.Type)
                else  [ { mapKey = "signing_key_files"
                        , mapValue =
                            arr (List/map Text JSON.Type str x.signing_key_files)
                        }
                      ]
              )
            # ( if    Prelude.List.null schema.UpstreamCache x.upstream_caches
                then  [] : List (Map/Entry Text JSON.Type)
                else  [ { mapKey = "upstream_caches"
                        , mapValue =
                            arr
                              ( List/map
                                  schema.UpstreamCache
                                  JSON.Type
                                  upstreamJSON
                                  x.upstream_caches
                              )
                        }
                      ]
              )
          )

let casWitnessSvcJSON =
      \(x : schema.CasWitnessSvc) ->
        obj
          [ { mapKey = "cas_store", mapValue = str x.cas_store }
          , { mapKey = "alias_store", mapValue = str x.alias_store }
          , { mapKey = "ca_cert_file", mapValue = str x.ca_cert_file }
          , { mapKey = "ca_key_file", mapValue = str x.ca_key_file }
          , { mapKey = "max_fetch_size_bytes"
            , mapValue = nat x.max_fetch_size_bytes
            }
          ]

let Opt/fold = https://prelude.dhall-lang.org/v23.0.0/Optional/fold.dhall

let optStrField =
      \(k : Text) ->
      \(v : Optional Text) ->
        Opt/fold
          Text
          v
          (List (Map/Entry Text JSON.Type))
          (\(s : Text) -> [ { mapKey = k, mapValue = str s } ])
          ([] : List (Map/Entry Text JSON.Type))

let ociRegistryJSON =
      \(x : schema.OciRegistry.Type) ->
        obj
          (   [ { mapKey = "host", mapValue = str x.host } ]
            # optStrField "scheme" x.scheme
            # optStrField "root_certificates" x.root_certificates
            # optStrField "username" x.username
            # optStrField "password" x.password
            # optStrField "bearer_token" x.bearer_token
            # ( if    x.insecure_skip_verify
                then  [ { mapKey = "insecure_skip_verify"
                        , mapValue = bool True
                        }
                      ]
                else  [] : List (Map/Entry Text JSON.Type)
              )
          )

let ociSelfRegistryJSON =
      \(x : schema.OciSelfRegistryRefs) ->
        obj
          [ { mapKey = "blob_store", mapValue = str x.blob_store }
          , { mapKey = "index_store", mapValue = str x.index_store }
          , { mapKey = "ref_store", mapValue = str x.ref_store }
          ]

let ociFetchJSON =
      \(x : schema.OciFetch.Type) ->
        obj
          (   optStrField "cas_store" x.cas_store
            # [ { mapKey = "dedup_check", mapValue = bool x.dedup_check }
              , { mapKey = "digest_function"
                , mapValue = str x.digest_function
                }
              , { mapKey = "registries"
                , mapValue =
                    arr
                      ( List/map
                          schema.OciRegistry.Type
                          JSON.Type
                          ociRegistryJSON
                          x.registries
                      )
                }
              ]
            # Opt/fold
                schema.OciSelfRegistryRefs
                x.self_registry
                (List (Map/Entry Text JSON.Type))
                ( \(sr : schema.OciSelfRegistryRefs) ->
                    [ { mapKey = "self_registry"
                      , mapValue = ociSelfRegistryJSON sr
                      }
                    ]
                )
                ([] : List (Map/Entry Text JSON.Type))
          )

let fetchSvcJSON =
      \(x : schema.FetchSvc.Type) ->
        obj
          (   [ { mapKey = "instance_name", mapValue = str x.instance_name }
              , { mapKey = "fetch_store", mapValue = str x.fetch_store }
              ]
            # Opt/fold
                schema.OciFetch.Type
                x.oci
                (List (Map/Entry Text JSON.Type))
                ( \(o : schema.OciFetch.Type) ->
                    [ { mapKey = "oci", mapValue = ociFetchJSON o } ]
                )
                ([] : List (Map/Entry Text JSON.Type))
          )

let ociRegistrySvcJSON =
      \(x : schema.OciRegistrySvc.Type) ->
        obj
          [ { mapKey = "instance_name", mapValue = str x.instance_name }
          , { mapKey = "cas_store", mapValue = str x.cas_store }
          , { mapKey = "index_store", mapValue = str x.index_store }
          , { mapKey = "ref_store", mapValue = str x.ref_store }
          , { mapKey = "digest_function", mapValue = str x.digest_function }
          , { mapKey = "spool_path", mapValue = str x.spool_path }
          , { mapKey = "read_only", mapValue = bool x.read_only }
          , { mapKey = "enable_delete", mapValue = bool x.enable_delete }
          ]

let serverToJSON =
      \(s : schema.Server.Type) ->
        let httpInner
            : List (Map/Entry Text JSON.Type)
            =   [ { mapKey = "socket_address", mapValue = str s.socket_address }
                , -- HTTP/2 flow control for large CAS ByteStream uploads. The
                  -- default per-stream window (~64 KiB) drains in a frame or two
                  -- of a multi-GiB blob; with a slow downstream shard that stalls
                  -- the stream to a mid-stream reset. Enable adaptive windows and
                  -- raise the initial stream/connection windows so a toolchain
                  -- upload lands in one shot.
                  { mapKey = "advanced_http"
                  , mapValue =
                      obj
                        [ { mapKey =
                              "experimental_http2_initial_stream_window_size"
                          , mapValue = nat 16777216
                          }
                        , { mapKey =
                              "experimental_http2_initial_connection_window_size"
                          , mapValue = nat 67108864
                          }
                        , { mapKey = "experimental_http2_adaptive_window"
                          , mapValue = bool True
                          }
                        ]
                  }
                ]
              # Opt/fold
                  schema.Tls
                  s.tls
                  (List (Map/Entry Text JSON.Type))
                  ( \(t : schema.Tls) ->
                      [ { mapKey = "tls"
                        , mapValue =
                            obj
                              [ { mapKey = "cert_file"
                                , mapValue = str t.cert_file
                                }
                              , { mapKey = "key_file"
                                , mapValue = str t.key_file
                                }
                              ]
                        }
                      ]
                  )
                  ([] : List (Map/Entry Text JSON.Type))

        let svc
            : List (Map/Entry Text JSON.Type)
            =   ( if    Prelude.List.null schema.CasSvc s.cas
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "cas"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.CasSvc
                                    JSON.Type
                                    casSvcJSON
                                    s.cas
                                )
                          }
                        ]
                )
              # ( if    Prelude.List.null schema.AcSvc s.ac
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "ac"
                          , mapValue =
                              arr
                                (List/map schema.AcSvc JSON.Type acSvcJSON s.ac)
                          }
                        ]
                )
              # ( if    Prelude.List.null schema.ExecSvc s.execution
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "execution"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.ExecSvc
                                    JSON.Type
                                    execSvcJSON
                                    s.execution
                                )
                          }
                        ]
                )
              # ( if    Prelude.List.null schema.CapSvc s.capabilities
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "capabilities"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.CapSvc
                                    JSON.Type
                                    capSvcJSON
                                    s.capabilities
                                )
                          }
                        ]
                )
              # ( if    Prelude.List.null schema.FetchSvc.Type s.fetch
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "fetch"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.FetchSvc.Type
                                    JSON.Type
                                    fetchSvcJSON
                                    s.fetch
                                )
                          }
                        ]
                )
              # ( if    Prelude.List.null schema.CasSvc s.bytestream
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "bytestream"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.CasSvc
                                    JSON.Type
                                    casSvcJSON
                                    s.bytestream
                                )
                          }
                        ]
                )
              # Opt/fold
                  Text
                  s.worker_api_scheduler
                  (List (Map/Entry Text JSON.Type))
                  ( \(sch : Text) ->
                      [ { mapKey = "worker_api"
                        , mapValue =
                            obj [ { mapKey = "scheduler", mapValue = str sch } ]
                        }
                      ]
                  )
                  ([] : List (Map/Entry Text JSON.Type))
              # ( if    Prelude.List.null schema.NixCacheSvc.Type s.nix_cache
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "nix_cache"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.NixCacheSvc.Type
                                    JSON.Type
                                    nixCacheSvcJSON
                                    s.nix_cache
                                )
                          }
                        ]
                )
              # ( if    Prelude.List.null
                          schema.OciRegistrySvc.Type
                          s.oci_registry
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "oci_registry"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.OciRegistrySvc.Type
                                    JSON.Type
                                    ociRegistrySvcJSON
                                    s.oci_registry
                                )
                          }
                        ]
                )
              # Opt/fold
                  schema.CasWitnessSvc
                  s.cas_witness
                  (List (Map/Entry Text JSON.Type))
                  ( \(w : schema.CasWitnessSvc) ->
                      [ { mapKey = "cas_witness"
                        , mapValue = casWitnessSvcJSON w
                        }
                      ]
                  )
                  ([] : List (Map/Entry Text JSON.Type))
              # ( if    s.admin
                  then  [ { mapKey = "admin"
                          , mapValue =
                              obj ([] : List (Map/Entry Text JSON.Type))
                          }
                        ]
                  else  [] : List (Map/Entry Text JSON.Type)
                )
              # ( if    s.health
                  then  [ { mapKey = "health"
                          , mapValue =
                              obj ([] : List (Map/Entry Text JSON.Type))
                          }
                        ]
                  else  [] : List (Map/Entry Text JSON.Type)
                )
              # ( if    s.prometheus
                  then  [ { mapKey = "experimental_prometheus"
                          , mapValue =
                              obj ([] : List (Map/Entry Text JSON.Type))
                          }
                        ]
                  else  [] : List (Map/Entry Text JSON.Type)
                )

        in  obj
              [ { mapKey = "name", mapValue = str s.name }
              , { mapKey = "listener"
                , mapValue =
                    obj [ { mapKey = "http", mapValue = obj httpInner } ]
                }
              , { mapKey = "services", mapValue = obj svc }
              ]

let workerToJSON =
      \(w : schema.Worker.Type) ->
        let localInner
            : List (Map/Entry Text JSON.Type)
            =   [ { mapKey = "worker_api_endpoint"
                  , mapValue =
                      obj
                        [ { mapKey = "uri"
                          , mapValue = str w.worker_api_endpoint
                          }
                        ]
                  }
                , { mapKey = "cas_fast_slow_store"
                  , mapValue = str w.cas_fast_slow_store
                  }
                , { mapKey = "upload_action_result"
                  , mapValue =
                      obj [ { mapKey = "ac_store", mapValue = str w.ac_store } ]
                  }
                , { mapKey = "work_directory", mapValue = str w.work_directory }
                , { mapKey = "platform_properties"
                  , mapValue =
                      obj
                        ( List/map
                            schema.PlatformProp
                            (Map/Entry Text JSON.Type)
                            ( \(p : schema.PlatformProp) ->
                                { mapKey = p.name
                                , mapValue =
                                    obj
                                      [ { mapKey = "values"
                                        , mapValue =
                                            arr
                                              ( List/map
                                                  Text
                                                  JSON.Type
                                                  str
                                                  p.values
                                              )
                                        }
                                      ]
                                }
                            )
                            w.platform_properties
                        )
                  }
                ]
              # Opt/fold
                  Text
                  w.entrypoint
                  (List (Map/Entry Text JSON.Type))
                  ( \(e : Text) ->
                      [ { mapKey = "entrypoint", mapValue = str e } ]
                  )
                  ([] : List (Map/Entry Text JSON.Type))

        in  obj [ { mapKey = "local", mapValue = obj localInner } ]

let renderConfig =
      \(c : schema.Config.Type) ->
        let top
            : List (Map/Entry Text JSON.Type)
            =   [ { mapKey = "stores"
                  , mapValue =
                      arr
                        ( List/map
                            schema.Store.Type
                            JSON.Type
                            storeToJSON
                            c.stores
                        )
                  }
                , { mapKey = "global"
                  , mapValue =
                      obj
                        [ { mapKey = "max_open_files"
                          , mapValue = nat c.max_open_files
                          }
                        ]
                  }
                ]
              # ( if    Prelude.List.null schema.Scheduler.Type c.schedulers
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "schedulers"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.Scheduler.Type
                                    JSON.Type
                                    schedToJSON
                                    c.schedulers
                                )
                          }
                        ]
                )
              # ( if    Prelude.List.null schema.Server.Type c.servers
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "servers"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.Server.Type
                                    JSON.Type
                                    serverToJSON
                                    c.servers
                                )
                          }
                        ]
                )
              # ( if    Prelude.List.null schema.Worker.Type c.workers
                  then  [] : List (Map/Entry Text JSON.Type)
                  else  [ { mapKey = "workers"
                          , mapValue =
                              arr
                                ( List/map
                                    schema.Worker.Type
                                    JSON.Type
                                    workerToJSON
                                    c.workers
                                )
                          }
                        ]
                )

        in  JSON.render (obj top)

in  { filesystem
    , memory
    , grpc
    , ref
    , fastSlow
    , fastSlowWriteBack
    , cacheMetrics
    , r2
    , verify
    , completeness
    , ShardEntry
    , shard
    , renderConfig
    }
