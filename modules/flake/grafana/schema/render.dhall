--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // grafana // render
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  Transforms our typed Dashboard into Grafana's JSON model.

let T = ./types.dhall

let List/map =
      \(a : Type) ->
      \(b : Type) ->
      \(f : a -> b) ->
      \(xs : List a) ->
        List/build
          b
          ( \(list : Type) ->
            \(cons : b -> list -> list) ->
            \(nil : list) ->
              List/fold a xs list (\(x : a) -> cons (f x)) nil
          )

let List/concatMap =
      \(a : Type) ->
      \(b : Type) ->
      \(f : a -> List b) ->
      \(xs : List a) ->
        List/build
          b
          ( \(list : Type) ->
            \(cons : b -> list -> list) ->
            \(nil : list) ->
              List/fold
                a
                xs
                list
                (\(x : a) -> List/fold b (f x) list cons)
                nil
          )

let renderTarget =
      \(t : T.Target.Type) ->
        { rawSql = t.rawSql
        , format = t.format
        , datasource = t.datasource
        , refId = "A"
        }

let renderPanel =
      \(p : T.Panel.Type) ->
        { type = T.panelTypeToGrafana p.type
        , title = p.title
        , gridPos = { x = 0, y = 0, w = p.width, h = p.height }
        , targets =
            List/map T.Target.Type _ renderTarget p.targets
        , fieldConfig = { defaults = { unit = T.unitToGrafana p.unit } }
        , datasource = T.Datasource.default
        }

let renderVariable =
      \(v : T.Variable.Type) ->
        { name = v.name
        , label = v.label
        , type = "query"
        , query = v.query
        , datasource = T.Datasource.default
        , multi = v.multi
        , includeAll = v.includeAll
        }

let renderDashboard =
      \(d : T.Dashboard.Type) ->
        { title = d.title
        , uid = d.uid
        , description = d.description
        , tags = d.tags
        , schemaVersion = 39
        , refresh = d.refresh
        , time = { from = d.timeFrom, to = "now" }
        , timezone = "browser"
        , editable = True
        , templating.list =
            List/map T.Variable.Type _ renderVariable d.variables
        , panels =
            List/concatMap
              T.Row.Type
              _
              ( \(row : T.Row.Type) ->
                  List/map T.Panel.Type _ renderPanel row.panels
              )
              d.rows
        }

in  renderDashboard
