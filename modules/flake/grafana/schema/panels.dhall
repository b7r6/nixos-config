--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // grafana // panels
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  panel constructors. each enforces the correct format, unit, and query pattern
--  so that the bugs we hit (wrong format, missing ORDER BY time, cumulative
--  counters shown as raw values) become impossible.

let T = ./types.dhall
let S = ./sql.dhall

-- ── stat panel (big number + sparkline) ────────────────────────────────────────
-- always format=Table (single value), 4×4 by default

let stat =
      \(title : Text) ->
      \(sql : Text) ->
        T.Panel::{
        , title = title
        , type = T.PanelType.Stat
        , sql = sql
        , format = T.Format.Table
        , width = 4
        , height = 4
        }

let statWithThreshold =
      \(title : Text) ->
      \(sql : Text) ->
      \(t : T.Thresholds.Type) ->
        T.Panel::{
        , title = title
        , type = T.PanelType.Stat
        , sql = sql
        , format = T.Format.Table
        , width = 4
        , height = 4
        , thresholds = Some t
        , colorMode = "background"
        }

-- ── time series panel (multi-series auto-pivot) ────────────────────────────────
-- always format=Auto (plugin pivots string columns into separate series)
-- requires: query result ordered by time (outer), columns: time + string(s) + value

let timeseries =
      \(title : Text) ->
      \(unit : T.Unit) ->
      \(sql : Text) ->
        T.Panel::{
        , title = title
        , type = T.PanelType.TimeSeries
        , sql = sql
        , format = T.Format.Auto
        , unit = unit
        }

let timeseriesWide =
      \(title : Text) ->
      \(unit : T.Unit) ->
      \(sql : Text) ->
        T.Panel::{
        , title = title
        , type = T.PanelType.TimeSeries
        , sql = sql
        , format = T.Format.Auto
        , unit = unit
        , width = 24
        }

let timeseriesStacked =
      \(title : Text) ->
      \(unit : T.Unit) ->
      \(sql : Text) ->
        T.Panel::{
        , title = title
        , type = T.PanelType.TimeSeries
        , sql = sql
        , format = T.Format.Auto
        , unit = unit
        , stacking = T.Stacking.Normal
        , fillOpacity = 80
        }

-- ── table panel ────────────────────────────────────────────────────────────────
-- always format=Table, full width by default

let table =
      \(title : Text) ->
      \(sql : Text) ->
        T.Panel::{
        , title = title
        , type = T.PanelType.Table
        , sql = sql
        , format = T.Format.Table
        , width = 24
        , height = 10
        }

-- ── gauge panel ────────────────────────────────────────────────────────────────

let gauge =
      \(title : Text) ->
      \(unit : T.Unit) ->
      \(sql : Text) ->
      \(t : T.Thresholds.Type) ->
        T.Panel::{
        , title = title
        , type = T.PanelType.Gauge
        , sql = sql
        , format = T.Format.Table
        , unit = unit
        , width = 6
        , height = 6
        , thresholds = Some t
        }

-- ── bar gauge panel ────────────────────────────────────────────────────────────

let barGauge =
      \(title : Text) ->
      \(sql : Text) ->
        T.Panel::{
        , title = title
        , type = T.PanelType.BarGauge
        , sql = sql
        , format = T.Format.Table
        , width = 8
        , height = 7
        }

-- ── pre-built panels using SQL helpers ─────────────────────────────────────────

-- stat: gauge metric current value
let statGauge =
      \(title : Text) ->
      \(metric : Text) ->
        stat title (S.statGauge metric)

-- stat: log count for a unit
let statLogs =
      \(title : Text) ->
      \(unitName : Text) ->
        stat title (S.statLogCount unitName)

-- stat: error count for a unit (with threshold)
let statErrors =
      \(title : Text) ->
      \(unitName : Text) ->
        statWithThreshold title (S.statLogErrors unitName) T.thresholdErrors

-- time series: log volume by severity (stacked)
let logVolume =
      \(title : Text) ->
      \(unitName : Text) ->
        timeseriesStacked title T.Unit.Short (S.logVolume unitName)

-- table: recent errors for a unit
let errorTable =
      \(title : Text) ->
      \(unitName : Text) ->
        table title (S.logErrors unitName 100)

in  { stat
    , statWithThreshold
    , timeseries
    , timeseriesWide
    , timeseriesStacked
    , table
    , gauge
    , barGauge
    , statGauge
    , statLogs
    , statErrors
    , logVolume
    , errorTable
    }
