-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                   // hypermodern // grafana // exit-rotation
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- mullvad exit-node rotation across the fleet (tailscale-exit-rotate.timer).
-- data source: the structured `exit-rotate: node=… cc=… city=… pool=…` journald
-- lines, shipped via the otel spine into otel_logs. no scraper, no push — the
-- log line IS the metric.

let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

-- all rotation events (incl. pool=0 no-op ticks from unenrolled hosts)
let f = "${S.unit} = 'tailscale-exit-rotate.service' AND ${S.msg} LIKE 'exit-rotate:%'"

-- only real hops
let hop = "${f} AND ${S.msg} LIKE '%node=%'"

let node = "extract(${S.msg}, 'node=([a-z0-9-]+)')"
let cc = "extract(${S.msg}, 'cc=([a-z]+)')"
let city = "extract(${S.msg}, 'city=([a-z]+)')"
let pool = "toUInt32OrZero(extract(${S.msg}, 'pool=([0-9]+)'))"

let dashboard =
      T.Dashboard::{
      , title = "Exit Rotation (Mullvad)"
      , uid = "exit-rotation"
      , tags = [ "tailscale", "mullvad", "fleet" ]
      , refresh = "1m"
      , timeFrom = "now-6h"
      , rows =
          [ T.Row::{
            , title = "Health"
            , panels =
                [ P.stat "Hosts rotating (1h)"
                    "SELECT uniq(${S.host}) as value FROM ${S.logs} WHERE ${hop} AND Timestamp > now() - INTERVAL 1 HOUR"
                , P.stat "Hops (24h)"
                    "SELECT count() as value FROM ${S.logs} WHERE ${hop} AND Timestamp > now() - INTERVAL 24 HOUR"
                , P.stat "Countries (24h)"
                    "SELECT uniq(${cc}) as value FROM ${S.logs} WHERE ${hop} AND Timestamp > now() - INTERVAL 24 HOUR"
                , P.stat "Exit pool size"
                    "SELECT ${pool} as value FROM ${S.logs} WHERE ${hop} ORDER BY Timestamp DESC LIMIT 1"
                , P.statWithThreshold "Unenrolled ticks (1h)"
                    "SELECT count() as value FROM ${S.logs} WHERE ${f} AND ${S.msg} LIKE '%pool=0%' AND Timestamp > now() - INTERVAL 1 HOUR"
                    T.thresholdErrors
                ]
            }
          , T.Row::{
            , title = "Rotation"
            , panels =
                [ (P.timeseriesStacked "Hops by host" T.Unit.Short
                    "SELECT toStartOfFifteenMinutes(Timestamp) as time, ${S.host} as host, count() as value FROM ${S.logs} WHERE ${hop} AND ${S.tfLog} GROUP BY time, host ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseriesStacked "Hops by country" T.Unit.Short
                    "SELECT toStartOfHour(Timestamp) as time, ${cc} as country, count() as value FROM ${S.logs} WHERE ${hop} AND ${S.tfLog} GROUP BY time, country ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Exit pool size by host" T.Unit.Short
                    "SELECT toStartOfFiveMinutes(Timestamp) as time, ${S.host} as host, max(${pool}) as value FROM ${S.logs} WHERE ${hop} AND ${S.tfLog} GROUP BY time, host ORDER BY time"
                  ) // { width = 8 }
                ]
            }
          , T.Row::{
            , title = "Where Are We Now"
            , panels =
                [ (P.table "Current exit per host"
                    "SELECT ${S.host} as host, argMax(${node}, Timestamp) as node, argMax(${cc}, Timestamp) as country, argMax(${city}, Timestamp) as city, max(Timestamp) as last_hop FROM ${S.logs} WHERE ${hop} AND Timestamp > now() - INTERVAL 24 HOUR GROUP BY host ORDER BY host"
                  ) // { width = 10, height = 8 }
                , (P.table "Recent hops"
                    "SELECT Timestamp, ${S.host} as host, ${node} as node, ${cc} as country, ${city} as city FROM ${S.logs} WHERE ${hop} AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 200"
                  ) // { width = 14, height = 8 }
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
