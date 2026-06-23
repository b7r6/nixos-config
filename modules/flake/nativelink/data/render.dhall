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
          [ { mapKey = "grpc"
            , mapValue =
                obj
                  [ { mapKey = "instance_name", mapValue = str instanceName }
                  , { mapKey = "store_type", mapValue = str storeType }
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

let fastSlow =
      \(fast : Backend) ->
      \(slow : Backend) ->
          [ { mapKey = "fast_slow"
            , mapValue =
                obj
                  [ { mapKey = "fast", mapValue = wrap fast }
                  , { mapKey = "fast_direction", mapValue = str "get" }
                  , { mapKey = "slow", mapValue = wrap slow }
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

let Opt/fold = https://prelude.dhall-lang.org/v23.0.0/Optional/fold.dhall

let serverToJSON =
      \(s : schema.Server.Type) ->
        let httpInner
            : List (Map/Entry Text JSON.Type)
            =   [ { mapKey = "socket_address", mapValue = str s.socket_address }
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
    , r2
    , ShardEntry
    , shard
    , renderConfig
    }
