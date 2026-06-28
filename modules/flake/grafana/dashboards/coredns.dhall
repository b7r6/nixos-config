-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                       // hypermodern // grafana // coredns
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- split-horizon fleet DNS. 5 nodes run CoreDNS.
-- 4 zones: authoritative (sju1.s4.gl), CNAME template (s4.gl),
--           tailnet forward (MagicDNS), catch-all (1.1.1.1/8.8.8.8).

let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let Q = ../schema/queries.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

-- ── DNS-specific helpers ───────────────────────────────────────────────────────

-- rate of a counter split by an attribute (rcode, type, zone, proto, etc.)
let dnsRate =
      \(metric : Text) ->
      \(attr : Text) ->
      \(alias : Text) ->
        "SELECT TimeUnix as time, Attributes['${attr}'] as ${alias}, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = '${metric}' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, ${alias} ORDER BY time"

-- rate of a counter split by upstream ('to' attribute)
let byUpstream =
      \(metric : Text) ->
        "SELECT TimeUnix as time, Attributes['to'] as upstream, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = '${metric}' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, upstream ORDER BY time"

-- ── variables ──────────────────────────────────────────────────────────────────

let hostVar =
      T.Variable::{
      , name = "host"
      , label = "Host"
      , type = T.VariableType.Query
      , query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1"
      , includeAll = True
      }

-- ═══════════════════════════════════════════════════════════════════════════════

let dashboard =
      T.Dashboard::{
      , title = "CoreDNS"
      , uid = "coredns"
      , tags = [ "dns", "coredns" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , variables = [ hostVar ]
      , rows =

          [ -- ── health ─────────────────────────────────────────────────────────
            T.Row::{
            , title = "Health"
            , panels =
                [ (P.stat "Queries/sec (fleet)"
                    "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) / 30 as rate FROM ${S.sum} WHERE MetricName = 'coredns_dns_requests_total' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0"
                  ) // { width = 4, unit = T.Unit.ReqPerSec }
                , (P.stat "Cache entries"
                    "SELECT sum(Value) as value FROM ${S.gauge} WHERE MetricName = 'coredns_cache_entries' AND TimeUnix > now() - INTERVAL 2 MINUTE"
                  ) // { width = 4 }
                , (P.statWithThreshold "SERVFAIL/sec"
                    "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) / 30 as rate FROM ${S.sum} WHERE MetricName = 'coredns_dns_responses_total' AND Attributes['rcode'] = 'SERVFAIL' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0"
                    T.thresholdErrors
                  ) // { width = 4 }
                , (P.statWithThreshold "Panics"
                    "SELECT sum(Value) as value FROM ${S.sum} WHERE MetricName = 'coredns_panics_total' AND TimeUnix > now() - INTERVAL 2 MINUTE"
                    { mode = "absolute", steps = [ { color = "green", value = None Natural }, { color = "red", value = Some 1 } ] }
                  ) // { width = 4 }
                , (P.stat "Nodes serving"
                    "SELECT uniq(${S.host}) as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_requests_total' AND TimeUnix > now() - INTERVAL 2 MINUTE"
                  ) // { width = 4 }
                , (P.statWithThreshold "HC failures"
                    "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) as rate FROM ${S.sum} WHERE MetricName = 'coredns_forward_healthcheck_broken_total' AND TimeUnix > now() - INTERVAL 5 MINUTE ORDER BY TimeUnix) WHERE rate >= 0"
                    T.thresholdErrors
                  ) // { width = 4 }
                ]
            }

          , -- ── query rate ─────────────────────────────────────────────────────
            T.Row::{
            , title = "Query Rate"
            , panels =
                [ P.timeseries "By node" T.Unit.ReqPerSec
                    (Q.rateByHost "coredns_dns_requests_total")
                , P.timeseries "By type (A, AAAA, PTR, SRV...)" T.Unit.ReqPerSec
                    (dnsRate "coredns_dns_requests_total" "type" "qtype")
                ]
            }

          , -- ── responses ──────────────────────────────────────────────────────
            T.Row::{
            , title = "Responses"
            , panels =
                [ (P.timeseriesStacked "By RCODE" T.Unit.ReqPerSec
                    (dnsRate "coredns_dns_responses_total" "rcode" "rcode")
                  ) // { fillOpacity = 60 }
                , (P.timeseries "NXDOMAIN + SERVFAIL" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['rcode'] as rcode, ${S.host} as node, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_responses_total' AND Attributes['rcode'] IN ('NXDOMAIN', 'SERVFAIL') AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, rcode, node ORDER BY time"
                  ) // { thresholds = Some T.thresholdErrors }
                ]
            }

          , -- ── plugins & latency ──────────────────────────────────────────────
            T.Row::{
            , title = "Plugins & Upstream"
            , panels =
                [ P.timeseries "Responses by plugin" T.Unit.Short
                    (dnsRate "coredns_dns_responses_total" "plugin" "plugin")
                , (P.timeseries "Proxy HC failures by upstream" T.Unit.Short
                    "SELECT TimeUnix as time, Attributes['to'] as upstream, runningDifference(Value) as value FROM ${S.sum} WHERE MetricName = 'coredns_proxy_healthcheck_failures_total' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"
                  ) // { thresholds = Some T.thresholdErrors }
                ]
            }

          , -- ── cache ──────────────────────────────────────────────────────────
            T.Row::{
            , title = "Cache"
            , panels =
                [ (P.timeseries "Hit rate" T.Unit.Percentunit
                    "SELECT h.TimeUnix as time, h.${S.host} as host, sum(h.Value) / (sum(h.Value) + sum(m.Value)) as value FROM ${S.sum} h INNER JOIN ${S.sum} m ON h.TimeUnix = m.TimeUnix AND h.${S.host} = m.${S.host} WHERE h.MetricName = 'coredns_cache_hits_total' AND m.MetricName = 'coredns_cache_misses_total' AND h.${S.tf} GROUP BY time, host ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Hits by type" T.Unit.ReqPerSec
                    (dnsRate "coredns_cache_hits_total" "type" "cache_type")
                  ) // { width = 8 }
                , (P.timeseries "Entries (current)" T.Unit.Short
                    "SELECT TimeUnix as time, ${S.host} as node, Attributes['type'] as cache_type, avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'coredns_cache_entries' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, node, cache_type ORDER BY time"
                  ) // { width = 8 }
                , P.timeseries "Misses by node" T.Unit.ReqPerSec
                    (Q.rateByHost "coredns_cache_misses_total")
                , P.timeseries "Requests by node" T.Unit.ReqPerSec
                    (Q.rateByHost "coredns_cache_requests_total")
                ]
            }

          , -- ── forwarding ─────────────────────────────────────────────────────
            T.Row::{
            , title = "Forwarding"
            , panels =
                [ P.timeseries "Conn cache hits by upstream" T.Unit.ReqPerSec
                    (byUpstream "coredns_proxy_conn_cache_hits_total")
                , P.timeseries "Conn cache misses by upstream" T.Unit.ReqPerSec
                    (byUpstream "coredns_proxy_conn_cache_misses_total")
                , (P.timeseries "All upstreams broken" T.Unit.Short
                    "SELECT TimeUnix as time, Attributes['to'] as upstream, runningDifference(Value) as value FROM ${S.sum} WHERE MetricName = 'coredns_forward_healthcheck_broken_total' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"
                  ) // { thresholds = Some T.thresholdErrors }
                , P.timeseries "Conn cache hits vs misses" T.Unit.ReqPerSec
                    (Q.rateByKey "coredns_proxy_conn_cache_hits_total" "MetricName" "metric")
                ]
            }

          , -- ── zones & protocol ───────────────────────────────────────────────
            T.Row::{
            , title = "Zones & Protocol"
            , panels =
                [ (P.timeseriesStacked "By zone" T.Unit.ReqPerSec
                    (dnsRate "coredns_dns_requests_total" "zone" "zone")
                  ) // { fillOpacity = 60 }
                , P.timeseries "Template matches (CNAME)" T.Unit.ReqPerSec
                    (Q.rateByHost "coredns_template_matches_total")
                , P.timeseries "By protocol (UDP/TCP)" T.Unit.ReqPerSec
                    (dnsRate "coredns_dns_requests_total" "proto" "proto")
                , P.timeseries "By family (IPv4/IPv6)" T.Unit.ReqPerSec
                    (dnsRate "coredns_dns_requests_total" "family" "family")
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
