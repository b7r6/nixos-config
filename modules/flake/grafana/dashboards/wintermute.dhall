-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                        // hypermodern // grafana // wintermute
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- The theme reconciler's accountability ledger, made legible. The daemon
-- publishes one audit JSON line per tick to journald:
--
--   {"wm": "audit", "gen": N, "slug": "...",
--    "acks": {"quickshell": N, "emacs": N, "tmux": N, "hyprland": N, "zellij": N}}
--
-- wintermute runs as a USER service, so the journald key is
-- _SYSTEMD_USER_UNIT (not _SYSTEMD_UNIT — the sql.dhall helper covers system
-- units only). MESSAGE is itself JSON: extract it as a string, then extract
-- from that. Per-surface lag = expected generation minus the surface's acked
-- generation; zero everywhere is the converged fixed point.
let T = ../schema/types.dhall

let S = ../schema/sql.dhall

let P = ../schema/panels.dhall

let R = ../schema/render.dhall

let msg = "JSONExtractString(Body, 'MESSAGE')"

let isAudit =
      "JSONExtractString(Body, '_SYSTEMD_USER_UNIT') = 'wintermute.service' AND JSONExtractString(${msg}, 'wm') = 'audit'"

let auditRows =
      "SELECT Timestamp, ${S.host} as host, JSONExtractInt(${msg}, 'gen') as gen, JSONExtractString(${msg}, 'slug') as slug, kv.1 as surface, kv.2 as ack FROM ${S.logs} ARRAY JOIN JSONExtractKeysAndValues(JSONExtractString(${msg}, 'acks'), 'Int64') as kv WHERE ${isAudit}"

let dashboard =
      T.Dashboard::{
      , title = "Wintermute"
      , uid = "wintermute"
      , tags = [ "theme", "wintermute", "rice" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , rows =
        [ T.Row::{
          , title = "Control Plane"
          , panels =
            [     P.stat
                    "Generation"
                    "SELECT max(JSONExtractInt(${msg}, 'gen')) as value FROM ${S.logs} WHERE ${isAudit} AND Timestamp > now() - INTERVAL 5 MINUTE"
              //  { width = 5, height = 5 }
            ,     P.statWithThreshold
                    "Max surface lag (5m)"
                    "SELECT max(lag) as value FROM (SELECT gen - ack as lag FROM (${auditRows}) WHERE Timestamp > now() - INTERVAL 5 MINUTE)"
                    T.thresholdErrors
              //  { width = 5, height = 5 }
            ,     P.stat
                    "Audit ticks/min"
                    "SELECT count() / 5 as value FROM ${S.logs} WHERE ${isAudit} AND Timestamp > now() - INTERVAL 5 MINUTE"
              //  { width = 5, height = 5 }
            ,     P.table
                    "Current vector"
                    "SELECT ${S.host} as host, JSONExtractInt(${msg}, 'gen') as gen, JSONExtractString(${msg}, 'slug') as slug, Timestamp as at FROM ${S.logs} WHERE ${isAudit} ORDER BY Timestamp DESC LIMIT 1 BY host"
              //  { width = 9, height = 5 }
            ]
          }
        , T.Row::{
          , title = "Surface Conformance"
          , panels =
            [ P.timeseries
                "Per-surface generation lag"
                T.Unit.Short
                "SELECT toStartOfMinute(Timestamp) as time, concat(host, ' · ', surface) as series, max(gen - ack) as value FROM (${auditRows}) WHERE ${S.tfLog} GROUP BY time, series ORDER BY time"
            ,     P.table
                    "Ack ledger (latest tick per host)"
                    "SELECT host, surface, ack, gen, gen - ack as lag, if(gen = ack, 'CONVERGED', 'LAGGING') as status FROM (${auditRows}) WHERE (host, Timestamp) IN (SELECT host, max(Timestamp) FROM (${auditRows}) GROUP BY host) ORDER BY host, surface"
              //  { height = 8 }
            ]
          }
        , T.Row::{
          , title = "Reconciler"
          , panels =
            [ P.timeseries
                "Daemon log volume"
                T.Unit.Short
                "SELECT toStartOfMinute(Timestamp) as time, count() as value FROM ${S.logs} WHERE JSONExtractString(Body, '_SYSTEMD_USER_UNIT') = 'wintermute.service' AND ${S.tfLog} GROUP BY time ORDER BY time"
            ,     P.table
                    "Recent daemon lines"
                    "SELECT Timestamp, ${S.host} as host, ${msg} as message FROM ${S.logs} WHERE JSONExtractString(Body, '_SYSTEMD_USER_UNIT') = 'wintermute.service' AND ${S.tfLog} ORDER BY Timestamp DESC LIMIT 50"
              //  { height = 9 }
            ]
          }
        ]
      }

in  R.renderDashboard dashboard
