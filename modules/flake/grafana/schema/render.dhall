--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // grafana // render
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  transforms typed Dashboard → Grafana JSON model.
--  handles grid layout, panel IDs, format codes, thresholds, stacking.
let T = ./types.dhall

let Prelude = ./Prelude/package.dhall

let JSON = Prelude.JSON

let GridPos = { x : Natural, y : Natural, w : Natural, h : Natural }

let renderPanel =
      \(id : Natural) ->
      \(pos : GridPos) ->
      \(p : T.Panel.Type) ->
        let thresholdJson =
              merge
                { Some =
                    \(t : T.Thresholds.Type) ->
                      JSON.object
                        ( toMap
                            { mode = JSON.string t.mode
                            , steps =
                                JSON.array
                                  ( Prelude.List.map
                                      T.ThresholdStep
                                      JSON.Type
                                      ( \(s : T.ThresholdStep) ->
                                          JSON.object
                                            ( toMap
                                                { color = JSON.string s.color
                                                , value =
                                                    merge
                                                      { Some =
                                                          \(v : Natural) ->
                                                            JSON.natural v
                                                      , None = JSON.null
                                                      }
                                                      s.value
                                                }
                                            )
                                      )
                                      t.steps
                                  )
                            }
                        )
                , None = JSON.null
                }
                p.thresholds

        let stackingJson =
              merge
                { None =
                    JSON.object
                      ( toMap
                          { mode = JSON.string "none", group = JSON.string "A" }
                      )
                , Normal =
                    JSON.object
                      ( toMap
                          { mode = JSON.string "normal"
                          , group = JSON.string "A"
                          }
                      )
                , Percent =
                    JSON.object
                      ( toMap
                          { mode = JSON.string "percent"
                          , group = JSON.string "A"
                          }
                      )
                }
                p.stacking

        in  JSON.object
              ( toMap
                  { id = JSON.natural id
                  , title = JSON.string p.title
                  , type = JSON.string (T.panelTypeToGrafana p.type)
                  , description = JSON.string p.description
                  , gridPos =
                      JSON.object
                        ( toMap
                            { x = JSON.natural pos.x
                            , y = JSON.natural pos.y
                            , w = JSON.natural pos.w
                            , h = JSON.natural pos.h
                            }
                        )
                  , datasource =
                      JSON.object
                        ( toMap
                            { type = JSON.string T.Datasource.default.type
                            , uid = JSON.string T.Datasource.default.uid
                            }
                        )
                  , targets =
                      JSON.array
                        [ JSON.object
                            ( toMap
                                { rawSql = JSON.string p.sql
                                , format = JSON.natural (T.formatToNat p.format)
                                , queryType = JSON.string "sql"
                                , refId = JSON.string "A"
                                }
                            )
                        ]
                  , fieldConfig =
                      JSON.object
                        ( toMap
                            { defaults =
                                JSON.object
                                  ( toMap
                                      { unit =
                                          JSON.string (T.unitToGrafana p.unit)
                                      , color =
                                          JSON.object
                                            ( toMap
                                                { mode = JSON.string p.colorMode
                                                }
                                            )
                                      , custom =
                                          JSON.object
                                            ( toMap
                                                { lineWidth = JSON.natural 1
                                                , fillOpacity =
                                                    JSON.natural p.fillOpacity
                                                , spanNulls = JSON.bool True
                                                , showPoints =
                                                    JSON.string "never"
                                                , stacking = stackingJson
                                                }
                                            )
                                      , thresholds = thresholdJson
                                      }
                                  )
                            }
                        )
                  , options =
                      JSON.object
                        ( toMap
                            { tooltip =
                                JSON.object
                                  ( toMap
                                      { mode = JSON.string "multi"
                                      , sort = JSON.string "desc"
                                      }
                                  )
                            , legend =
                                JSON.object
                                  ( toMap
                                      { displayMode = JSON.string "table"
                                      , placement = JSON.string "bottom"
                                      , calcs =
                                          JSON.array
                                            [ JSON.string "mean"
                                            , JSON.string "max"
                                            , JSON.string "last"
                                            ]
                                      }
                                  )
                            }
                        )
                  }
              )

let renderRow =
      \(id : Natural) ->
      \(y : Natural) ->
      \(title : Text) ->
        JSON.object
          ( toMap
              { id = JSON.natural id
              , title = JSON.string title
              , type = JSON.string "row"
              , gridPos =
                  JSON.object
                    ( toMap
                        { x = JSON.natural 0
                        , y = JSON.natural y
                        , w = JSON.natural 24
                        , h = JSON.natural 1
                        }
                    )
              , collapsed = JSON.bool False
              , panels = JSON.array ([] : List JSON.Type)
              }
          )

let renderVariable =
      \(v : T.Variable.Type) ->
        let typeStr =
              merge
                { Query = "query", Textbox = "textbox", Custom = "custom" }
                v.type

        in  JSON.object
              ( toMap
                  { name = JSON.string v.name
                  , label = JSON.string v.label
                  , type = JSON.string typeStr
                  , query = JSON.string v.query
                  , datasource =
                      JSON.object
                        ( toMap
                            { type = JSON.string T.Datasource.default.type
                            , uid = JSON.string T.Datasource.default.uid
                            }
                        )
                  , multi = JSON.bool v.multi
                  , includeAll = JSON.bool v.includeAll
                  }
              )

let renderDashboard =
      \(d : T.Dashboard.Type) ->
        let State = { panels : List JSON.Type, nextId : Natural, y : Natural }

        let initState = { panels = [] : List JSON.Type, nextId = 1, y = 0 }

        let processRow =
              \(state : State) ->
              \(r : T.Row.Type) ->
                let rowPanel = renderRow state.nextId state.y r.title

                let afterRow =
                      { panels = state.panels # [ rowPanel ]
                      , nextId = state.nextId + 1
                      , y = state.y + 1
                      }

                let PanelState =
                      { panels : List JSON.Type
                      , nextId : Natural
                      , x : Natural
                      , y : Natural
                      , maxRowH : Natural
                      }

                let initPanelState =
                      { panels = afterRow.panels
                      , nextId = afterRow.nextId
                      , x = 0
                      , y = afterRow.y
                      , maxRowH = 0
                      }

                let processPanel =
                      \(ps : PanelState) ->
                      \(p : T.Panel.Type) ->
                        let needsWrap =
                              Prelude.Natural.greaterThan (ps.x + p.width) 24

                        let x = if needsWrap then 0 else ps.x

                        let y = if needsWrap then ps.y + ps.maxRowH else ps.y

                        let maxH =
                              if    needsWrap
                              then  p.height
                              else  if Prelude.Natural.greaterThan
                                         p.height
                                         ps.maxRowH
                              then  p.height
                              else  ps.maxRowH

                        let pos = { x, y, w = p.width, h = p.height }

                        let panelJson = renderPanel ps.nextId pos p

                        in  { panels = ps.panels # [ panelJson ]
                            , nextId = ps.nextId + 1
                            , x = x + p.width
                            , y
                            , maxRowH = maxH
                            }

                let finalPanelState =
                      Prelude.List.foldLeft
                        T.Panel.Type
                        PanelState
                        r.panels
                        initPanelState
                        processPanel

                in  { panels = finalPanelState.panels
                    , nextId = finalPanelState.nextId
                    , y = finalPanelState.y + finalPanelState.maxRowH
                    }

        let finalState =
              Prelude.List.foldLeft T.Row.Type State d.rows initState processRow

        in  JSON.object
              ( toMap
                  { title = JSON.string d.title
                  , uid = JSON.string d.uid
                  , schemaVersion = JSON.natural 39
                  , refresh = JSON.string d.refresh
                  , time =
                      JSON.object
                        ( toMap
                            { from = JSON.string d.timeFrom
                            , to = JSON.string "now"
                            }
                        )
                  , timezone = JSON.string "browser"
                  , editable = JSON.bool True
                  , tags =
                      JSON.array
                        (Prelude.List.map Text JSON.Type JSON.string d.tags)
                  , templating =
                      JSON.object
                        ( toMap
                            { list =
                                JSON.array
                                  ( Prelude.List.map
                                      T.Variable.Type
                                      JSON.Type
                                      renderVariable
                                      d.variables
                                  )
                            }
                        )
                  , panels = JSON.array finalState.panels
                  }
              )

in  { renderPanel, renderRow, renderVariable, renderDashboard }
