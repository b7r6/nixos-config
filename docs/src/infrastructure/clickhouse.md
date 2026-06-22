# ClickHouse production architecture (design)

> Status by stage:
> - **Design — THIS DOC.** Topology, module shape, Keeper ensemble, R2-disk
>   tiering, and the Prometheus/Grafana → ClickHouse migration, all grounded in
>   the repo's existing conventions (`postgres.nix`, `registry.nix`, the topology
>   registry, `state.nix`, `backup.nix`).
> - **Stage 1 — Keeper ensemble — TODO.** 3-node `clickhouse-keeper` across
>   ultraviolence / guccimane / shimmer (the coordination plane). Stand it up and
>   prove quorum first; it's the part with no upstream NixOS module.
> - **Stage 2 — ClickHouse server (watchtower) — TODO.** Single server, S3 disk
>   to R2, talking to the *remote* Keeper ensemble. Replicated MergeTree + `ON
>   CLUSTER` DDL wired even at one server, so scale-out is a topology edit.
> - **Stage 3 — Observability migration — TODO.** Grafana stays; swap the storage
>   engine under it (Prometheus remote-write → ClickHouse), then decommission
>   Prometheus TSDB. Add log/trace ingestion.
> - **Stage 4 — OLAP scratch + app backing store — TODO.** General analytical
>   workloads once the platform is proven.
>
> This is a **dress rehearsal for production at scale**: every choice (separate
> Keeper plane, multi-arch ensemble, replicated engines, S3 tiering, `ON CLUSTER`
> DDL) is made as if the homelab were the real fleet, so the patterns transfer
> to heavy-metal deployment unchanged.

## The deliberate topology

```
                         coordination plane (Keeper ensemble, 3-node)
        ┌────────────────────┬────────────────────┬────────────────────┐
        │  ultraviolence      │  guccimane          │  shimmer            │
        │  x86_64             │  x86_64             │  aarch64            │
        │  keeper id=1        │  keeper id=2        │  keeper id=3        │
        │  100.71.82.73       │  100.89.101.109     │  100.116.42.95      │
        └─────────┬───────────┴──────────┬──────────┴──────────┬─────────┘
                  └──────────── Raft over the tailnet (:9234) ──┘
                                      ▲
                                      │ ZooKeeper protocol (:9181) over tailnet
                                      │
                            ┌─────────┴──────────┐
                            │   watchtower        │   data plane (ClickHouse server)
                            │   x86_64            │   :8123 HTTP (loopback → nginx)
                            │   100.122.228.122   │   :9000 native (tailscale0)
                            │   /var/lib/clickhouse  (S3 disk → R2)
                            └────────────────────┘
```

Two properties are **on test by design**, not by convenience:

1. **Keeper is not co-located with the server.** The textbook layout puts Keeper
   next to (or on) the ClickHouse nodes. We deliberately separate the coordination
   plane onto three *other* hosts, reached over the tailnet. This exercises the
   failure mode that actually bites in production — coordination latency/partition
   between the server and its quorum — instead of hiding it behind loopback.
2. **The ensemble is multi-arch.** shimmer is aarch64 (DGX-class), ultraviolence
   and guccimane are x86_64. Raft quorum across heterogeneous arches is a real
   SBSA-fleet concern; we prove it small. (Unlike the nativelink aarch64 worker,
   aarch64 `clickhouse` builds and substitutes cleanly today — Keeper on shimmer
   is viable now.)

Why 3 nodes: Raft tolerates `floor((n-1)/2)` failures, so a 3-node ensemble
survives **one** node down (quorum = 2). That's the smallest ensemble that is
actually fault-tolerant; 1 node is a toy, 2 nodes is *worse* than 1 (any single
loss breaks quorum).

## Why ClickHouse Keeper (not ZooKeeper), from day one

ClickHouse needs a coordination service for **replication** and **distributed
DDL** (`ON CLUSTER`). The legacy answer is ZooKeeper (JVM); the modern answer is
**ClickHouse Keeper** — a C++ reimplementation of the ZooKeeper protocol, shipped
*in the same `clickhouse` binary* (`clickhouse keeper`), using Raft (NuRaft)
instead of ZAB. We use Keeper exclusively:

- One binary, one package, no JVM — fits the nix closure cleanly and substitutes
  multi-arch.
- It's the production direction; "get good at Keeper" is an explicit goal here.
- Even with a **single** ClickHouse server we run the full ensemble and use
  `ReplicatedMergeTree` + `ON CLUSTER`, so adding a second server later is a
  registry edit, not a schema rewrite. **Provision for the cluster you'll have,
  not the node you have.**

### No upstream NixOS module for Keeper

nixpkgs ships `services.clickhouse` (server only) but **no `services.clickhouse-keeper`**.
So Keeper is a **hand-rolled systemd service** around `clickhouse keeper -C
<config>` — the same "no upstream module, wrap the binary" situation as
[nativelink](./nativelink.md). This is the novel part of the module work; the
server half largely delegates to the upstream module.

## Module shape (mirrors `postgres.nix` + `registry.nix`)

A single `modules/nixos/clickhouse.nix` under `hyper-modern-nixos.databases.clickhouse`
(the tightest analogy to the existing `databases.postgres`), gated `enable = false`,
added to `modules/nixos/default.nix`. It exposes two **independently-enableable**
roles via a `lib.mkMerge` of gated blocks (the postgres idiom):

- `databases.clickhouse.keeper.*` — the Keeper role (the ensemble members enable
  this).
- `databases.clickhouse.server.*` — the ClickHouse server role (watchtower
  enables this).

A host can enable either or both. Sketch of the option surface:

```nix
hyper-modern-nixos.databases.clickhouse = {
  # ── Keeper role (ultraviolence / guccimane / shimmer) ──
  keeper = {
    enable = true;
    id = 1;                       # 1/2/3, unique per node; the Raft server_id
    # ensemble derived from the topology registry (hosts tagged "clickhouse-keeper")
    tailnet.interface = "tailscale0";   # :9181 client + :9234 raft, tailnet-only
  };

  # ── Server role (watchtower) ──
  server = {
    enable = true;
    # keeper endpoints derived from the registry (the 3 tagged hosts : :9181)
    listenLoopback = true;        # 8123 on 127.0.0.1 → nginx; 9000 on tailscale0
    s3 = {
      enable = true;
      bucket = "straylight-clickhouse";
      endpoint = "https://<acct>.r2.cloudflarestorage.com";
      environmentSecret = "clickhouse-r2-env";   # self-wired agenix; AWS_* creds
    };
  };
};
```

Conventions it inherits, by reference:

- **Args/secrets:** `{ config, lib, pkgs, flake ? null, ... }`,
  `machineSecrets = flake.self + "/secrets/agenix/machines"`; secrets self-wired by
  name and consumed via `EnvironmentFile` + `restartTriggers` (the
  [registry](../services/registry.md) / [secrets](./secrets.md) pattern), never
  the store.
- **Firewall:** tailnet-scoped only — `networking.firewall.interfaces.tailscale0.allowedTCPPorts`.
  Keeper opens `9181` (client) + `9234` (raft); server opens `9000` (native).
  Nothing internet-facing.
- **State class:** with the S3 disk, the local dir is a cache (truth is in R2), so
  `hyper-modern-nixos.state.dirs.clickhouse = { path = "/var/lib/clickhouse"; class
  = "reconstructible"; }` — same posture as attic/zot/nativelink, so restic does
  **not** drag the data tier. Keeper's coordination log is small and local
  (`/var/lib/clickhouse-keeper`); classed `reconstructible` too (it rebuilds from
  quorum/snapshots).

## Keeper config (the ensemble)

Each node renders `keeper_config.xml` with its own `server_id` and the shared
`raft_configuration` listing all three by tailnet name. The ensemble is **derived
from the topology registry** — hosts tagged `clickhouse-keeper` — so adding/moving
a node is a `registry/hosts.dhall` edit + re-render, exactly like CoreDNS service
CNAMEs. Shape:

```xml
<keeper_server>
  <tcp_port>9181</tcp_port>
  <server_id>1</server_id>            <!-- per node -->
  <coordination_settings>
    <operation_timeout_ms>10000</operation_timeout_ms>
    <session_timeout_ms>30000</session_timeout_ms>
  </coordination_settings>
  <raft_configuration>
    <server><id>1</id><hostname>ultraviolence.osiris-walleye.ts.net</hostname><port>9234</port></server>
    <server><id>2</id><hostname>guccimane.osiris-walleye.ts.net</hostname><port>9234</port></server>
    <server><id>3</id><hostname>shimmer.osiris-walleye.ts.net</hostname><port>9234</port></server>
  </raft_configuration>
</keeper_server>
```

Notes for the WAN-ish (tailnet) separation:
- Timeouts are bumped from the co-located defaults because Raft now crosses the
  tailnet, not loopback. Tuning these *is* part of the resilience rehearsal.
- Use MagicDNS names (`*.osiris-walleye.ts.net`), which resolve fleet-wide via the
  CoreDNS forward block (see [networking](../architecture/networking.md)). The
  tailnet IPs are stable in the registry if we'd rather pin.
- Ops via `clickhouse-keeper-client` (`mntr`, `srvr`, `ruok`) — the resilience
  drills (kill a node, confirm quorum holds; kill two, confirm it stops; restart,
  confirm rejoin) run against this.

## ClickHouse server → remote Keeper

watchtower's server points `<zookeeper>` at the three remote Keeper endpoints:

```xml
<zookeeper>
  <node><host>ultraviolence.osiris-walleye.ts.net</host><port>9181</port></node>
  <node><host>guccimane.osiris-walleye.ts.net</host><port>9181</port></node>
  <node><host>shimmer.osiris-walleye.ts.net</host><port>9181</port></node>
</zookeeper>
<distributed_ddl><path>/clickhouse/task_queue/ddl</path></distributed_ddl>
```

A `<remote_servers>` cluster (`fleet`) is defined even with one shard/replica, so
all DDL is `CREATE TABLE … ON CLUSTER fleet` and all tables are
`ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')`. Adding a
second server later = add it to the cluster def + the registry; the macros and
zk paths already exist.

## S3 disk → R2 (reconstructible)

A storage policy with an `s3` disk backed by the R2 bucket `straylight-clickhouse`,
fronted by a small local cache disk:

```xml
<storage_configuration>
  <disks>
    <s3>
      <type>s3</type>
      <endpoint>https://<acct>.r2.cloudflarestorage.com/straylight-clickhouse/</endpoint>
      <!-- creds from /run/agenix/clickhouse-r2-env via env, never inline -->
    </s3>
    <s3_cache><type>cache</type><disk>s3</disk><path>/var/lib/clickhouse/s3cache/</path>
      <max_size>100Gi</max_size></s3_cache>
  </disks>
  <policies><s3_main><volumes><main><disk>s3_cache</disk></main></volumes></s3_main></policies>
</storage_configuration>
```

R2 is the durable truth; the local cache (and thus `/var/lib/clickhouse`) is
`reconstructible`. This is the same "truth in R2, local tier is a cache" model as
attic and the nativelink CAS — the fleet's house pattern. Credentials come from
the self-wired `clickhouse-r2-env` agenix secret (`AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY`), added to `secrets/secrets.nix` as a `mkGlobalSecret`,
alongside `zot-r2-env` / `nativelink-r2-env` / `pgbackrest-r2-env`.

## Topology / DNS

- Tag watchtower's `services` with `clickhouse`; tag ultraviolence/guccimane/shimmer
  with `clickhouse-keeper` in `registry/hosts.dhall`, then `nix run .#topology-render`.
- CoreDNS then resolves `clickhouse.sju1.s4.gl` → watchtower automatically (the
  service-CNAME mechanism), and the Keeper nodes are reachable by their existing
  host names.
- nginx fronts the HTTP interface: `hyper-modern-nixos.reverseProxy.services.clickhouse.port
  = 8123` → `clickhouse.sju1.s4.gl` on the wildcard cert (zot's pattern). The
  native protocol (`:9000`) and Keeper ports stay tailnet-only (nginx can't proxy
  them).

## Migration: monitoring → ClickHouse (OTel spine + phased UI)

The fleet's metrics live in Prometheus/Grafana today (watchtower's `monitoring`
service tag). The migration has two independent axes — the **ingestion spine** and
the **UI** — and the plan commits to the spine immediately while phasing the UI.

### The spine: OpenTelemetry collector → ClickHouse (commit now)

**Recommendation: adopt the OTel-native ingestion spine from the start.** OTel
"used to suck" — that's dated. `opentelemetry-collector-contrib` is **0.151 in our
nixpkgs**, the **ClickHouse exporter** is a stable contrib component, and OTLP is
now the lingua franca for logs + metrics + traces in one pipeline. This replaces
the straylight `vmagent` + `fluent-bit` + scrape model (prior art under
`straylight-infra/nix/nixos/services/monitoring/`) with **one collector per host**:

- A lightweight **host collector** (`otelcol-contrib`) on each fleet node: scrapes
  node/exporter metrics (`prometheus` receiver — existing exporters keep working),
  tails journald (`journald`/`filelog` receiver), accepts app OTLP, and exports via
  OTLP to watchtower.
- A **central collector** on watchtower with the **`clickhouse` exporter** writing
  logs/metrics/traces into the ClickHouse server (S3-disk → R2). Batched inserts,
  the exporter manages its MergeTree schemas (with TTL).

This is worth doing regardless of which UI wins, because the schema and pipeline
are identical either way — nothing downstream is wasted.

### The UI: Grafana first, HyperDX/ClickStack as the headline (phased)

You asked for the new hotness — **ClickStack (HyperDX)** — and that's the right
end state, but a two-phase rollout de-risks it:

**Phase 1 — Grafana + ClickHouse datasource (immediate).** Grafana is already the
fleet's pane of glass (straylight runs Grafana over VictoriaMetrics; we repoint
it). Add the **official ClickHouse datasource plugin**, panels as SQL, dashboards
provisioned-as-code — a clean nix module, zero new runtime deps. Gets
visualizations on ClickHouse on day one and lets us validate the OTel→CH data
against the existing dashboards side-by-side.

**Phase 2 — ClickStack / HyperDX (the headline UI).** ClickHouse's own opensource
observability stack: the **HyperDX UI** (Lucene + SQL search, trace waterfalls,
session replay, log-pattern recognition, APM — all CH-native and correlated, "no
tool-switching"), fed by the **same OTel collector** we already run. It slots on
top of the *same* ClickHouse data with **no re-instrumentation**.

> **Packaging caveat (why it's Phase 2, not Phase 1).** HyperDX is **not in
> nixpkgs**, and ClickStack OSS also needs a **MongoDB** instance for app state
> (dashboards/users/config). So HyperDX is a real packaging project: most likely
> a `dockerTools`/OCI image served from our [zot registry](../services/registry.md)
> + a hand-rolled `hyper-modern-nixos` module + a small MongoDB, presented via
> nginx like the other web services. Tracked on the [TODO frontier](../todo-frontier.md).
> The OTel spine + ClickHouse schema are identical whether the UI is Grafana or
> HyperDX, so Phase 1 is not throwaway.

### Cutover sequence (no data cliff)

1. **Land the platform** (Stages 1–2): Keeper ensemble + ClickHouse server, proven
   healthy, before touching monitoring.
2. **Dual-run the spine.** Stand up the OTel collectors writing to ClickHouse while
   the existing Prometheus/VM stack keeps running. Both pipelines live; nothing
   removed.
3. **Grafana on ClickHouse.** Add the ClickHouse datasource, rebuild key dashboards
   against it, validate side-by-side with the incumbent.
4. **Cut over reads.** Point Grafana's default at ClickHouse; the old TSDB becomes
   a short safety-net retention window. Retention/rollups now live in ClickHouse
   via MergeTree **TTL** + materialized-view rollups — strictly more capable than
   flat TSDB retention.
5. **Decommission the old TSDB** once ClickHouse-backed dashboards/alerts are
   trusted; collapse to the single OTel→ClickHouse pipeline.
6. **HyperDX (Phase 2).** Package + deploy ClickStack on the same data; it becomes
   the primary O11y surface, Grafana stays for SQL/ops dashboards.

Net: **OTel is the one ingestion spine; ClickHouse is the one store for
metrics+logs+traces; Grafana gives visualizations immediately and HyperDX becomes
the headline correlated-O11y UI** — and we've rehearsed the production cluster
shape (separate multi-arch Keeper plane, replicated engines, `ON CLUSTER` DDL, S3
tiering) underneath it all.

## Prior art: the straylight-infra Keeper module

`~/src/straylight/straylight-infra/nix/nixos/services/clickhouse-keeper.nix` is a
working Keeper module to **start from** (plus a NixOS check at
`nix/nixos/checks/clickhouse-keeper.nix` and a kazoo-based smoke-test package at
`nix/packages/clickhouse-keeper-smoke-test/`). Adopt its mechanics:

- **`server_id` derived from the node's index** in the `nodes` list
  (`findFirstIndex + 1`) — no manual per-node `id`; the list *is* the ensemble.
- The `genNodesCfg0`/`genNodesCfg1` XML generators that emit `<raft_configuration>`,
  `<zookeeper>`, and `<remote_servers>` from the nodes list.
- Assertions: nodes unique, **odd** count, **≥ 3**.
- The smoke-test oneshot (`kazoo` CRUD against `:9181`) as a post-start health gate
  and the basis for the resilience drills + the NixOS check.

**The one deliberate divergence:** that module **co-locates** Keeper with a
ClickHouse server on *every* node (it enables `services.clickhouse` alongside
keeper). Our topology splits them — Keeper-only on the three ensemble nodes,
ClickHouse-only on watchtower — so we lift the keeper-config generation but **drop
the co-located `services.clickhouse`** from the keeper role, and source the `nodes`
list from the topology registry (`clickhouse-keeper` service tag) rather than a
hand-passed list. Raft port follows the prior art (`9444`).

## Build stages (each lands and is proven before the next)

1. **Keeper ensemble** — Keeper-only `clickhouse keeper` service on the three nodes
   (adapted from the straylight module, co-located server dropped), derived from
   the registry. Prove quorum + run the resilience drills (one-node-loss survives,
   two-node-loss halts, rejoin recovers) via the smoke test + a NixOS check.
2. **ClickHouse server** — watchtower, S3 disk → R2, talking to the *remote*
   ensemble; `ON CLUSTER` DDL + `ReplicatedMergeTree` smoke test.
3. **OTel ingestion spine** — `otelcol-contrib` host collectors → central
   collector with the `clickhouse` exporter; dual-run alongside the existing
   Prometheus/VM stack.
4. **Visualization (Phase 1)** — Grafana + ClickHouse datasource; cut dashboards
   over, decommission the old TSDB.
5. **Visualization (Phase 2)** — package + deploy ClickStack/HyperDX (OCI via zot +
   MongoDB + module) as the headline correlated-O11y UI on the same data.
6. **OLAP scratch + app backing store** — general workloads on the proven platform.
