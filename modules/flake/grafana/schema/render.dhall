--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // grafana // render
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  transforms typed Dashboard → plain Dhall records that dhall-to-json serializes
--  directly to Grafana's JSON model. no Church-encoded JSON, no Prelude.JSON.
--
--  the output record types mirror Grafana's schema:
--    Dashboard → { title, uid, panels : List PanelJSON, ... }
--    PanelJSON → { id, title, type, gridPos, targets, fieldConfig, ... }
let T = ./types.dhall

let Prelude = ./Prelude/package.dhall

let GridPos = { x : Natural, y : Natural, w : Natural, h : Natural }

let TargetJSON =
      { rawSql : Text, format : Natural, queryType : Text, refId : Text }

let ThresholdStepJSON = { color : Text, value : Optional Natural }

let ThresholdsJSON = { mode : Text, steps : List ThresholdStepJSON }

let StackingJSON = { mode : Text, group : Text }

let CustomJSON =
      { lineWidth : Natural
      , fillOpacity : Natural
      , spanNulls : Bool
      , showPoints : Text
      , stacking : StackingJSON
      }

let ColorJSON = { mode : Text }

let DefaultsJSON =
      { unit : Text
      , color : ColorJSON
      , custom : CustomJSON
      , thresholds : Optional ThresholdsJSON
      }

let FieldConfigJSON = { defaults : DefaultsJSON }

let TooltipJSON = { mode : Text, sort : Text }

let LegendJSON = { displayMode : Text, placement : Text, calcs : List Text }

let OptionsJSON = { tooltip : TooltipJSON, legend : LegendJSON }

let DatasourceJSON = { type : Text, uid : Text }

let VariableJSON =
      { name : Text
      , label : Text
      , type : Text
      , query : Text
      , datasource : DatasourceJSON
      , multi : Bool
      , includeAll : Bool
      }

let FullPanelJSON =
      { id : Natural
      , title : Text
      , type : Text
      , description : Text
      , gridPos : GridPos
      , datasource : DatasourceJSON
      , targets : List TargetJSON
      , fieldConfig : FieldConfigJSON
      , options : OptionsJSON
      , collapsed : Bool
      }

let TimeJSON = { from : Text, to : Text }

let TemplatingJSON = { list : List VariableJSON }

let DashboardJSON =
      { title : Text
      , uid : Text
      , schemaVersion : Natural
      , refresh : Text
      , time : TimeJSON
      , timezone : Text
      , editable : Bool
      , tags : List Text
      , templating : TemplatingJSON
      , panels : List FullPanelJSON
      }

let defaultDs
    : DatasourceJSON
    = { type = T.Datasource.default.type, uid = T.Datasource.default.uid }

let emptyFieldConfig
    : FieldConfigJSON
    = { defaults =
        { unit = "short"
        , color.mode = "palette-classic"
        , custom =
          { lineWidth = 1
          , fillOpacity = 10
          , spanNulls = True
          , showPoints = "never"
          , stacking = { mode = "none", group = "A" }
          }
        , thresholds = None ThresholdsJSON
        }
      }

let defaultOptions
    : OptionsJSON
    = { tooltip = { mode = "multi", sort = "desc" }
      , legend =
        { displayMode = "table"
        , placement = "bottom"
        , calcs = [ "mean", "max", "last" ]
        }
      }

let makePanel =
      \(id : Natural) ->
      \(pos : GridPos) ->
      \(p : T.Panel.Type) ->
        let stackJson
            : StackingJSON
            = merge
                { None = { mode = "none", group = "A" }
                , Normal = { mode = "normal", group = "A" }
                , Percent = { mode = "percent", group = "A" }
                }
                p.stacking

        let threshJson
            : Optional ThresholdsJSON
            = merge
                { Some =
                    \(t : T.Thresholds.Type) ->
                      Some
                        { mode = t.mode
                        , steps =
                            Prelude.List.map
                              T.ThresholdStep
                              ThresholdStepJSON
                              ( \(s : T.ThresholdStep) ->
                                  { color = s.color, value = s.value }
                              )
                              t.steps
                        }
                , None = None ThresholdsJSON
                }
                p.thresholds

        in    { id
              , title = p.title
              , type = T.panelTypeToGrafana p.type
              , description = p.description
              , gridPos = pos
              , datasource = defaultDs
              , targets =
                [ { rawSql = p.sql
                  , format = T.formatToNat p.format
                  , queryType = "sql"
                  , refId = "A"
                  }
                ]
              , fieldConfig.defaults
                =
                { unit = T.unitToGrafana p.unit
                , color.mode = p.colorMode
                , custom =
                  { lineWidth = 1
                  , fillOpacity = p.fillOpacity
                  , spanNulls = True
                  , showPoints = "never"
                  , stacking = stackJson
                  }
                , thresholds = threshJson
                }
              , options = defaultOptions
              , collapsed = False
              }
            : FullPanelJSON

let makeRow =
      \(id : Natural) ->
      \(y : Natural) ->
      \(title : Text) ->
          { id
          , title
          , type = "row"
          , description = ""
          , gridPos = { x = 0, y, w = 24, h = 1 }
          , datasource = defaultDs
          , targets = [] : List TargetJSON
          , fieldConfig = emptyFieldConfig
          , options = defaultOptions
          , collapsed = False
          }
        : FullPanelJSON

let makeVariable =
      \(v : T.Variable.Type) ->
          { name = v.name
          , label = v.label
          , type =
              merge
                { Query = "query", Textbox = "textbox", Custom = "custom" }
                v.type
          , query = v.query
          , datasource = defaultDs
          , multi = v.multi
          , includeAll = v.includeAll
          }
        : VariableJSON

let renderDashboard =
      \(d : T.Dashboard.Type) ->
        let State =
              { panels : List FullPanelJSON, nextId : Natural, y : Natural }

        let initState = { panels = [] : List FullPanelJSON, nextId = 1, y = 0 }

        let processRow =
              \(state : State) ->
              \(r : T.Row.Type) ->
                let rowPanel = makeRow state.nextId state.y r.title

                let afterRow =
                      { panels = state.panels # [ rowPanel ]
                      , nextId = state.nextId + 1
                      , y = state.y + 1
                      }

                let PState =
                      { panels : List FullPanelJSON
                      , nextId : Natural
                      , x : Natural
                      , y : Natural
                      , maxH : Natural
                      }

                let initPS =
                      { panels = afterRow.panels
                      , nextId = afterRow.nextId
                      , x = 0
                      , y = afterRow.y
                      , maxH = 0
                      }

                let processPanel =
                      \(ps : PState) ->
                      \(p : T.Panel.Type) ->
                        let wrap =
                              Prelude.Natural.greaterThan (ps.x + p.width) 24

                        let x = if wrap then 0 else ps.x

                        let y = if wrap then ps.y + ps.maxH else ps.y

                        let maxH =
                              if    wrap
                              then  p.height
                              else  if Prelude.Natural.greaterThan
                                         p.height
                                         ps.maxH
                              then  p.height
                              else  ps.maxH

                        let panelJson =
                              makePanel
                                ps.nextId
                                { x, y, w = p.width, h = p.height }
                                p

                        in  { panels = ps.panels # [ panelJson ]
                            , nextId = ps.nextId + 1
                            , x = x + p.width
                            , y
                            , maxH
                            }

                let finalPS =
                      Prelude.List.foldLeft
                        T.Panel.Type
                        PState
                        r.panels
                        initPS
                        processPanel

                in  { panels = finalPS.panels
                    , nextId = finalPS.nextId
                    , y = finalPS.y + finalPS.maxH
                    }

        let finalState =
              Prelude.List.foldLeft T.Row.Type State d.rows initState processRow

        in    { title = d.title
              , uid = d.uid
              , schemaVersion = 39
              , refresh = d.refresh
              , time = { from = d.timeFrom, to = "now" }
              , timezone = "browser"
              , editable = True
              , tags = d.tags
              , templating.list
                =
                  Prelude.List.map
                    T.Variable.Type
                    VariableJSON
                    makeVariable
                    d.variables
              , panels = finalState.panels
              }
            : DashboardJSON

in  { renderDashboard }
