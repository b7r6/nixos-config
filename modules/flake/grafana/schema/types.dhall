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
--    - Text panels (markdown `content`, no query) and one-bar-per-row bar gauges

-- ── datasource ─────────────────────────────────────────────────────────────────
let Datasource =
      { Type = { type : Text, uid : Text }
      , default = { type = "grafana-clickhouse-datasource", uid = "clickhouse" }
      }

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
      | CurrencyUSD
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
          , CurrencyUSD = "currencyUSD"
          , None = "none"
          }
          u

let PanelType =
      < TimeSeries
      | Stat
      | Gauge
      | Table
      | Logs
      | BarGauge
      | Heatmap
      | Text
      | Row
      >

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
          , Text = "text"
          , Row = "row"
          }
          t

let Format = < Auto | Table >

let formatToNat = \(f : Format) -> merge { Auto = 0, Table = 2 } f

let ThresholdStep = { color : Text, value : Optional Natural }

let Thresholds =
      { Type = { mode : Text, steps : List ThresholdStep }
      , default =
        { mode = "absolute"
        , steps =
            [ { color = "green", value = None Natural } ] : List ThresholdStep
        }
      }

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

let Stacking = < None | Normal | Percent >

-- How a series chart shows its legend. `List` is the quiet default (names
-- only, bottom); `Table` adds mean/max/last for charts people read numbers
-- off; `Hidden` for a chart whose title already names its only series.
let Legend = < Hidden | List | Table >

let legendToGrafana =
      \(l : Legend) ->
        merge
          { Hidden = { displayMode = "list", placement = "bottom", calcs = [] : List Text, showLegend = False }
          , List = { displayMode = "list", placement = "bottom", calcs = [] : List Text, showLegend = True }
          , Table = { displayMode = "table", placement = "bottom", calcs = [ "mean", "max", "lastNotNull" ], showLegend = True }
          }
          l

let Target =
      { Type = { sql : Text, format : Format, refId : Text }
      , default = { sql = "", format = Format.Auto, refId = "A" }
      }

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
          , content : Text
          , datasource : Optional Datasource.Type
          , decimals : Optional Natural
          , min : Optional Natural
          , legend : Legend
          , noValue : Text
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
        , colorMode = "none"
        , content = ""
        , datasource = None Datasource.Type
        , decimals = None Natural
        , min = None Natural
        , legend = Legend.List
        , noValue = "no data in range"
        }
      }

let Row =
      { Type = { title : Text, panels : List Panel.Type, collapsed : Bool }
      , default =
        { title = "", panels = [] : List Panel.Type, collapsed = False }
      }

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

-- ── datasource variable ─────────────────────────────────────────────────────
-- a `type = "datasource"` template variable: the viewer picks which datasource
-- every panel and query variable of the dashboard binds to (`${name}` as the
-- dashboard's datasource uid). `regex` narrows the candidates by datasource
-- NAME; `current` is the one selected when the URL says nothing.
let DatasourceVariable =
      { Type =
          { name : Text
          , label : Text
          , pluginType : Text
          , regex : Text
          , current : { text : Text, value : Text }
          }
      , default =
        { label = "", pluginType = Datasource.default.type, regex = "" }
      }

let Dashboard =
      { Type =
          { title : Text
          , uid : Text
          , tags : List Text
          , refresh : Text
          , timeFrom : Text
          , rows : List Row.Type
          , variables : List Variable.Type
          , datasourceVariables : List DatasourceVariable.Type
          , datasource : Datasource.Type
          }
      , default =
        { title = ""
        , uid = ""
        , tags = [] : List Text
        , refresh = "30s"
        , timeFrom = "now-1h"
        , rows = [] : List Row.Type
        , variables = [] : List Variable.Type
        , datasourceVariables = [] : List DatasourceVariable.Type
        , datasource = Datasource.default
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
    , Legend
    , legendToGrafana
    , Target
    , Panel
    , Row
    , Variable
    , VariableType
    , DatasourceVariable
    , Dashboard
    }
