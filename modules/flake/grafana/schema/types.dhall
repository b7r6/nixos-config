--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                   // hypermodern // grafana // types
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  Typed Grafana dashboard schema in Dhall. Compiles to Grafana's JSON model.
--  No UUIDs, no pixel math, no 2000-line blobs. Compose panels from primitives.

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
      | Percent0to1
      | OpsPerSec
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
          , Percent0to1 = "percentunit"
          , OpsPerSec = "ops"
          , None = "none"
          }
          u

let PanelType =
      < TimeSeries | Stat | Gauge | Table | Logs | BarGauge | Heatmap >

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
          }
          t

let Target =
      { Type =
          { rawSql : Text
          , format : Text  -- "time_series" | "table" | "logs"
          , datasource : Datasource.Type
          }
      , default =
          { rawSql = ""
          , format = "time_series"
          , datasource = Datasource.default
          }
      }

let Panel =
      { Type =
          { title : Text
          , type : PanelType
          , targets : List Target.Type
          , unit : Unit
          , width : Natural   -- grid units (1-24)
          , height : Natural  -- grid units
          , description : Text
          }
      , default =
          { title = ""
          , type = PanelType.TimeSeries
          , targets = [] : List Target.Type
          , unit = Unit.None
          , width = 12
          , height = 8
          , description = ""
          }
      }

let Row =
      { Type = { title : Text, panels : List Panel.Type, collapsed : Bool }
      , default = { title = "", panels = [] : List Panel.Type, collapsed = False }
      }

let Variable =
      { Type =
          { name : Text
          , label : Text
          , query : Text
          , multi : Bool
          , includeAll : Bool
          }
      , default =
          { name = ""
          , label = ""
          , query = ""
          , multi = False
          , includeAll = False
          }
      }

let Dashboard =
      { Type =
          { title : Text
          , uid : Text
          , description : Text
          , tags : List Text
          , refresh : Text
          , timeFrom : Text
          , rows : List Row.Type
          , variables : List Variable.Type
          }
      , default =
          { title = ""
          , uid = ""
          , description = ""
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
    , Target
    , Panel
    , Row
    , Variable
    , Dashboard
    }
