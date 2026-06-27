--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // grafana // types
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  "the sky above the port was the color of television, tuned to a dead channel."
--
--  typed grafana dashboard schema. the render pass handles:
--    - auto grid layout (row sections, panel width/height → x/y positions)
--    - format=0 (auto-pivot multi-series) for time series, format=2 for tables
--    - $host IN() variable filter pattern
--    - runningDifference rate pattern with ORDER BY time wrapper
--    - threshold steps with color coding
--    - stacking/fillOpacity field config

-- ── datasource ─────────────────────────────────────────────────────────────────

let Datasource =
      { Type = { type : Text, uid : Text }
      , default = { type = "grafana-clickhouse-datasource", uid = "clickhouse" }
      }

-- ── units ──────────────────────────────────────────────────────────────────────

let Unit =
      < Percent
      | Bytes
      | BytesPerSec
      | Short
      | Seconds
      | Milliseconds
      | Percentunit
      | OpsPerSec
      | ReqPerSec
      | RowsPerSec
      | QueriesPerSec
      | None
      >

let unitToGrafana =
      \(u : Unit) ->
        merge
          { Percent = "percent"
          , Bytes = "bytes"
          , BytesPerSec = "Bps"
          , Short = "short"
          , Seconds = "s"
          , Milliseconds = "ms"
          , Percentunit = "percentunit"
          , OpsPerSec = "ops"
          , ReqPerSec = "reqps"
          , RowsPerSec = "rows/s"
          , QueriesPerSec = "qps"
          , None = "none"
          }
          u

-- ── panel types ────────────────────────────────────────────────────────────────

let PanelType =
      < TimeSeries | Stat | Gauge | Table | Logs | BarGauge | Heatmap | Row >

let panelTypeToGrafana =
      \(t : PanelType) ->
        merge
          { TimeSeries = "timeseries"
          , Stat = "stat"
          , Gauge = "gauge"
          , Table = "table"
          , Logs = "logs"
          , BarGauge = "bargauge"
          , Heatmap = "heatmap"
          , Row = "row"
          }
          t

-- ── format (clickhouse plugin) ─────────────────────────────────────────────────
-- 0 = auto (pivots string columns into multi-frame time series)
-- 2 = table (raw rows, no pivot)

let Format = < Auto | Table >

let formatToNat =
      \(f : Format) ->
        merge { Auto = 0, Table = 2 } f

-- ── thresholds ─────────────────────────────────────────────────────────────────

let ThresholdStep = { color : Text, value : Optional Natural }

let Thresholds =
      { Type = { mode : Text, steps : List ThresholdStep }
      , default =
          { mode = "absolute"
          , steps = [ { color = "green", value = None Natural } ] : List ThresholdStep
          }
      }

-- common threshold presets
let thresholdPct =
      { mode = "percentage"
      , steps =
          [ { color = "green", value = None Natural }
          , { color = "yellow", value = Some 70 }
          , { color = "red", value = Some 90 }
          ]
      }

let thresholdLoad =
      { mode = "absolute"
      , steps =
          [ { color = "green", value = None Natural }
          , { color = "yellow", value = Some 4 }
          , { color = "red", value = Some 8 }
          ]
      }

let thresholdErrors =
      { mode = "absolute"
      , steps =
          [ { color = "green", value = None Natural }
          , { color = "yellow", value = Some 1 }
          , { color = "red", value = Some 10 }
          ]
      }

let thresholdHealth =
      { mode = "absolute"
      , steps =
          [ { color = "red", value = None Natural }
          , { color = "green", value = Some 1 }
          ]
      }

-- ── stacking ───────────────────────────────────────────────────────────────────

let Stacking = < None | Normal | Percent >

-- ── target (query) ─────────────────────────────────────────────────────────────

let Target =
      { Type =
          { sql : Text
          , format : Format
          , refId : Text
          }
      , default =
          { sql = ""
          , format = Format.Auto
          , refId = "A"
          }
      }

-- ── panel ──────────────────────────────────────────────────────────────────────

let Panel =
      { Type =
          { title : Text
          , type : PanelType
          , sql : Text
          , format : Format
          , unit : Unit
          , width : Natural
          , height : Natural
          , description : Text
          , thresholds : Optional Thresholds.Type
          , stacking : Stacking
          , fillOpacity : Natural
          , colorMode : Text
          }
      , default =
          { title = ""
          , type = PanelType.TimeSeries
          , sql = ""
          , format = Format.Auto
          , unit = Unit.Short
          , width = 12
          , height = 8
          , description = ""
          , thresholds = None Thresholds.Type
          , stacking = Stacking.None
          , fillOpacity = 10
          , colorMode = "palette-classic"
          }
      }

-- ── row (section divider) ──────────────────────────────────────────────────────

let Row =
      { Type = { title : Text, panels : List Panel.Type, collapsed : Bool }
      , default = { title = "", panels = [] : List Panel.Type, collapsed = False }
      }

-- ── variable ───────────────────────────────────────────────────────────────────

let VariableType = < Query | Textbox | Custom >

let Variable =
      { Type =
          { name : Text
          , label : Text
          , type : VariableType
          , query : Text
          , multi : Bool
          , includeAll : Bool
          }
      , default =
          { name = ""
          , label = ""
          , type = VariableType.Query
          , query = ""
          , multi = False
          , includeAll = False
          }
      }

-- ── dashboard ──────────────────────────────────────────────────────────────────

let Dashboard =
      { Type =
          { title : Text
          , uid : Text
          , tags : List Text
          , refresh : Text
          , timeFrom : Text
          , rows : List Row.Type
          , variables : List Variable.Type
          }
      , default =
          { title = ""
          , uid = ""
          , tags = [] : List Text
          , refresh = "30s"
          , timeFrom = "now-1h"
          , rows = [] : List Row.Type
          , variables = [] : List Variable.Type
          }
      }

in  { Datasource
    , Unit
    , unitToGrafana
    , PanelType
    , panelTypeToGrafana
    , Format
    , formatToNat
    , ThresholdStep
    , Thresholds
    , thresholdPct
    , thresholdLoad
    , thresholdErrors
    , thresholdHealth
    , Stacking
    , Target
    , Panel
    , Row
    , Variable
    , VariableType
    , Dashboard
    }
