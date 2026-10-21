--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // grafana // panels
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  panel constructors. each enforces the correct format, unit, and query pattern
--  so that the bugs we hit (wrong format, missing ORDER BY time, cumulative
--  counters shown as raw values) become impossible.
let T = ./types.dhall

let S = ./sql.dhall

let stat =
      \(title : Text) ->
      \(sql : Text) ->
        T.Panel::{
        , title
        , type = T.PanelType.Stat
        , sql
        , format = T.Format.Table
        , width = 4
        , height = 4
        }

let statWithThreshold =
      \(title : Text) ->
      \(sql : Text) ->
      \(t : T.Thresholds.Type) ->
        T.Panel::{
        , title
        , type = T.PanelType.Stat
        , sql
        , format = T.Format.Table
        , width = 4
        , height = 4
        , thresholds = Some t
        , colorMode = "value"
        }

let timeseries =
      \(title : Text) ->
      \(unit : T.Unit) ->
      \(sql : Text) ->
        T.Panel::{
        , title
        , type = T.PanelType.TimeSeries
        , sql
        , format = T.Format.Auto
        , unit
        , min = Some 0
        }

let timeseriesWide =
      \(title : Text) ->
      \(unit : T.Unit) ->
      \(sql : Text) ->
        T.Panel::{
        , title
        , type = T.PanelType.TimeSeries
        , sql
        , format = T.Format.Auto
        , unit
        , width = 24
        , min = Some 0
        }

let timeseriesStacked =
      \(title : Text) ->
      \(unit : T.Unit) ->
      \(sql : Text) ->
        T.Panel::{
        , title
        , type = T.PanelType.TimeSeries
        , sql
        , format = T.Format.Auto
        , unit
        , stacking = T.Stacking.Normal
        , fillOpacity = 80
        , min = Some 0
        }

let table =
      \(title : Text) ->
      \(sql : Text) ->
        T.Panel::{
        , title
        , type = T.PanelType.Table
        , sql
        , format = T.Format.Table
        , width = 24
        , height = 10
        }

let gauge =
      \(title : Text) ->
      \(unit : T.Unit) ->
      \(sql : Text) ->
      \(t : T.Thresholds.Type) ->
        T.Panel::{
        , title
        , type = T.PanelType.Gauge
        , sql
        , format = T.Format.Table
        , unit
        , width = 6
        , height = 6
        , thresholds = Some t
        }

let barGauge =
      \(title : Text) ->
      \(sql : Text) ->
        T.Panel::{
        , title
        , type = T.PanelType.BarGauge
        , sql
        , format = T.Format.Table
        , width = 8
        , height = 7
        }

let statGauge =
      \(title : Text) -> \(metric : Text) -> stat title (S.statGauge metric)

let statLogs =
      \(title : Text) ->
      \(unitName : Text) ->
        stat title (S.statLogCount unitName)

let statErrors =
      \(title : Text) ->
      \(unitName : Text) ->
        statWithThreshold title (S.statLogErrors unitName) T.thresholdErrors

let logVolume =
      \(title : Text) ->
      \(unitName : Text) ->
        timeseriesStacked title T.Unit.Short (S.logVolume unitName)

--  The same three over a row predicate (S.statLogCountWhere etc.).
let statLogsWhere =
      \(title : Text) ->
      \(predicate : Text) ->
        stat title (S.statLogCountWhere predicate)

let statErrorsWhere =
      \(title : Text) ->
      \(predicate : Text) ->
        statWithThreshold title (S.statLogErrorsWhere predicate) T.thresholdErrors

let logVolumeWhere =
      \(title : Text) ->
      \(predicate : Text) ->
        timeseriesStacked title T.Unit.Short (S.logVolumeWhere predicate)

let errorTable =
      \(title : Text) ->
      \(unitName : Text) ->
        table title (S.logErrors unitName 100)

let timeseriesSingle =
      \(title : Text) ->
      \(unit : T.Unit) ->
      \(sql : Text) ->
        timeseries title unit sql // { legend = T.Legend.Hidden }

in  { stat
    , statWithThreshold
    , timeseries
    , timeseriesWide
    , timeseriesSingle
    , timeseriesStacked
    , table
    , gauge
    , barGauge
    , statGauge
    , statLogs
    , statErrors
    , logVolume
    , statLogsWhere
    , statErrorsWhere
    , logVolumeWhere
    , errorTable
    }
