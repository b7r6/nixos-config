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

        let Line = List T.Panel.Type

        let processRow =
              \(state : State) ->
              \(r : T.Row.Type) ->
                let rowPanel = makeRow state.nextId state.y r.title

                let afterRow =
                      { panels = state.panels # [ rowPanel ]
                      , nextId = state.nextId + 1
                      , y = state.y + 1
                      }

                -- Pass 1: greedily group panels into lines that fit in 24 cols.
                let GroupAcc = { lines : List Line, cur : Line, curW : Natural }

                let groupInit =
                      { lines = [] : List Line, cur = [] : Line, curW = 0 }

                let groupStep =
                      \(a : GroupAcc) ->
                      \(p : T.Panel.Type) ->
                        if    Prelude.Natural.greaterThan (a.curW + p.width) 24
                        then  { lines = a.lines # [ a.cur ]
                              , cur = [ p ]
                              , curW = p.width
                              }
                        else  { lines = a.lines
                              , cur = a.cur # [ p ]
                              , curW = a.curW + p.width
                              }

                let grouped =
                      Prelude.List.foldLeft
                        T.Panel.Type
                        GroupAcc
                        r.panels
                        groupInit
                        groupStep

                let allLines =
                      grouped.lines
                      # (       if Natural/isZero
                                    (List/length T.Panel.Type grouped.cur)
                          then  [] : List Line
                          else  [ grouped.cur ]
                        )

                -- Pass 2: lay each line out at a uniform height (the line's
                -- tallest panel) and stretch it to fill all 24 cols — the last
                -- panel absorbs the slack, so no ragged edge, no short-panel gap.
                let LayoutAcc =
                      { panels : List FullPanelJSON
                      , nextId : Natural
                      , y : Natural
                      }

                let layoutLine =
                      \(la : LayoutAcc) ->
                      \(line : Line) ->
                        let maxH =
                              Prelude.List.foldLeft
                                T.Panel.Type
                                Natural
                                line
                                0
                                ( \(acc : Natural) ->
                                  \(p : T.Panel.Type) ->
                                    if    Prelude.Natural.greaterThan
                                            p.height
                                            acc
                                    then  p.height
                                    else  acc
                                )

                        let sumW =
                              Prelude.List.foldLeft
                                T.Panel.Type
                                Natural
                                line
                                0
                                ( \(acc : Natural) ->
                                  \(p : T.Panel.Type) ->
                                    acc + p.width
                                )

                        let slack = Natural/subtract sumW 24

                        let n = List/length T.Panel.Type line

                        let EmitAcc =
                              { panels : List FullPanelJSON
                              , nextId : Natural
                              , x : Natural
                              , i : Natural
                              }

                        let emitStep =
                              \(ea : EmitAcc) ->
                              \(p : T.Panel.Type) ->
                                let isLast =
                                      Natural/isZero
                                        (Natural/subtract (ea.i + 1) n)

                                let w =
                                      if isLast then p.width + slack else p.width

                                let panelJson =
                                      makePanel
                                        ea.nextId
                                        { x = ea.x, y = la.y, w, h = maxH }
                                        p

                                in  { panels = ea.panels # [ panelJson ]
                                    , nextId = ea.nextId + 1
                                    , x = ea.x + w
                                    , i = ea.i + 1
                                    }

                        let emitted =
                              Prelude.List.foldLeft
                                T.Panel.Type
                                EmitAcc
                                line
                                { panels = la.panels
                                , nextId = la.nextId
                                , x = 0
                                , i = 0
                                }
                                emitStep

                        in  { panels = emitted.panels
                            , nextId = emitted.nextId
                            , y = la.y + maxH
                            }

                let laidOut =
                      Prelude.List.foldLeft
                        Line
                        LayoutAcc
                        allLines
                        { panels = afterRow.panels
                        , nextId = afterRow.nextId
                        , y = afterRow.y
                        }
                        layoutLine

                in  { panels = laidOut.panels
                    , nextId = laidOut.nextId
                    , y = laidOut.y
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
