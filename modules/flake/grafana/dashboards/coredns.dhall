let T = ../schema/types.dhall
let S = ../schema/sql.dhall
let P = ../schema/panels.dhall
let R = ../schema/render.dhall

let hostVar = T.Variable::{ name = "host", label = "Host", type = T.VariableType.Query, query = "SELECT DISTINCT ${S.host} FROM ${S.gauge} WHERE TimeUnix > now() - INTERVAL 1 HOUR ORDER BY 1", includeAll = True }

let dashboard =
      T.Dashboard::{
      , title = "CoreDNS"
      , uid = "coredns"
      , tags = [ "dns", "coredns" ]
      , refresh = "30s"
      , timeFrom = "now-1h"
      , variables = [ hostVar ]
      , rows =
          [ T.Row::{
            , title = "Health"
            , panels =
                [ (P.stat "Queries/sec (fleet)" "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) / 30 as rate FROM ${S.sum} WHERE MetricName = 'coredns_dns_requests_total' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0") // { unit = T.Unit.ReqPerSec }
                , (P.stat "Cache entries" "SELECT sum(Value) as value FROM ${S.gauge} WHERE MetricName = 'coredns_cache_entries' AND TimeUnix > now() - INTERVAL 2 MINUTE")
                , (P.statWithThreshold "SERVFAIL/sec" "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) / 30 as rate FROM ${S.sum} WHERE MetricName = 'coredns_dns_responses_total' AND Attributes['rcode'] = 'SERVFAIL' AND TimeUnix > now() - INTERVAL 2 MINUTE ORDER BY TimeUnix) WHERE rate >= 0" T.thresholdErrors)
                , (P.statWithThreshold "Panics" "SELECT sum(Value) as value FROM ${S.sum} WHERE MetricName = 'coredns_panics_total' AND TimeUnix > now() - INTERVAL 2 MINUTE" { mode = "absolute", steps = [ { color = "green", value = None Natural }, { color = "red", value = Some 1 } ] })
                , (P.stat "Nodes serving DNS" "SELECT uniq(${S.host}) as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_requests_total' AND TimeUnix > now() - INTERVAL 2 MINUTE")
                , (P.statWithThreshold "Healthcheck failures" "SELECT sum(rate) as value FROM (SELECT runningDifference(Value) as rate FROM ${S.sum} WHERE MetricName = 'coredns_forward_healthcheck_broken_total' AND TimeUnix > now() - INTERVAL 5 MINUTE ORDER BY TimeUnix) WHERE rate >= 0" T.thresholdErrors)
                ]
            }
          , T.Row::{
            , title = "Query Rate"
            , panels =
                [ (P.timeseries "Queries/sec by node" T.Unit.ReqPerSec
                    (S.rateByKey "coredns_dns_requests_total" S.host "node")
                  )
                , P.timeseries "Queries/sec by type (A, AAAA, PTR, SRV, ...)" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['type'] as qtype, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_requests_total' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, qtype ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Responses & RCODEs"
            , panels =
                [ (P.timeseriesStacked "Responses/sec by RCODE" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['rcode'] as rcode, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_responses_total' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, rcode ORDER BY time"
                  ) // { fillOpacity = 60 }
                , (P.timeseries "NXDOMAIN + SERVFAIL rate" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['rcode'] as rcode, ${S.host} as node, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_responses_total' AND Attributes['rcode'] IN ('NXDOMAIN', 'SERVFAIL') AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, rcode, node ORDER BY time"
                  ) // { thresholds = Some T.thresholdErrors }
                ]
            }
          , T.Row::{
            , title = "Latency"
            , panels =
                [ P.timeseries "Responses/sec by plugin" T.Unit.Short
                    "SELECT TimeUnix as time, Attributes['plugin'] as plugin, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_responses_total' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, plugin ORDER BY time"
                , (P.timeseries "Proxy healthcheck failures by upstream" T.Unit.Short
                    "SELECT TimeUnix as time, Attributes['to'] as upstream, runningDifference(Value) as value FROM ${S.sum} WHERE MetricName = 'coredns_proxy_healthcheck_failures_total' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"
                  ) // { thresholds = Some T.thresholdErrors }
                ]
            }
          , T.Row::{
            , title = "Cache"
            , panels =
                [ (P.timeseries "Cache hit rate (success + denial)" T.Unit.Percentunit
                    "SELECT h.TimeUnix as time, h.${S.host} as host, sum(h.Value) / (sum(h.Value) + sum(m.Value)) as value FROM ${S.sum} h INNER JOIN ${S.sum} m ON h.TimeUnix = m.TimeUnix AND h.${S.host} = m.${S.host} WHERE h.MetricName = 'coredns_cache_hits_total' AND m.MetricName = 'coredns_cache_misses_total' AND h.${S.tf} GROUP BY time, host ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Cache hits/sec by type" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['type'] as cache_type, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_cache_hits_total' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, cache_type ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Cache entries (current)" T.Unit.Short
                    "SELECT TimeUnix as time, ${S.host} as node, Attributes['type'] as cache_type, avg(Value) as value FROM ${S.gauge} WHERE MetricName = 'coredns_cache_entries' AND ${S.tf} AND ${S.hostFilter} GROUP BY time, node, cache_type ORDER BY time"
                  ) // { width = 8 }
                , (P.timeseries "Cache misses/sec by node" T.Unit.ReqPerSec
                    (S.rateByKey "coredns_cache_misses_total" S.host "node")
                  )
                , (P.timeseries "Cache requests/sec (total lookups)" T.Unit.ReqPerSec
                    (S.rateByKey "coredns_cache_requests_total" S.host "node")
                  )
                ]
            }
          , T.Row::{
            , title = "Forwarding (Upstreams)"
            , panels =
                [ P.timeseries "Proxy conn cache hits/sec by upstream" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['to'] as upstream, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_proxy_conn_cache_hits_total' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, upstream ORDER BY time"
                , P.timeseries "Proxy conn cache misses/sec by upstream" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['to'] as upstream, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_proxy_conn_cache_misses_total' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, upstream ORDER BY time"
                , (P.timeseries "Upstream healthcheck failures" T.Unit.Short
                    "SELECT TimeUnix as time, Attributes['to'] as upstream, runningDifference(Value) as value FROM ${S.sum} WHERE MetricName = 'coredns_forward_healthcheck_broken_total' AND ${S.tf} AND runningDifference(Value) >= 0 ORDER BY time"
                  ) // { thresholds = Some T.thresholdErrors }
                , P.timeseries "Connection cache hits vs misses" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, MetricName as metric, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName IN ('coredns_proxy_conn_cache_hits_total', 'coredns_proxy_conn_cache_misses_total') AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, metric ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Zones & Templates"
            , panels =
                [ (P.timeseriesStacked "Queries by zone" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['zone'] as zone, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_requests_total' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, zone ORDER BY time"
                  ) // { fillOpacity = 60 }
                , P.timeseries "Cache requests vs hits/sec" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, MetricName as metric, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName IN ('coredns_cache_requests_total', 'coredns_cache_hits_total') AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, metric ORDER BY time"
                ]
            }
          , T.Row::{
            , title = "Protocol Breakdown"
            , panels =
                [ P.timeseries "Queries by protocol (UDP vs TCP)" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['proto'] as proto, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_requests_total' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, proto ORDER BY time"
                , P.timeseries "Queries by family (IPv4 vs IPv6)" T.Unit.ReqPerSec
                    "SELECT TimeUnix as time, Attributes['family'] as family, sum(runningDifference(Value)) / 30 as value FROM ${S.sum} WHERE MetricName = 'coredns_dns_requests_total' AND ${S.tf} AND runningDifference(Value) >= 0 GROUP BY time, family ORDER BY time"
                ]
            }
          ]
      }

in  R.renderDashboard dashboard
