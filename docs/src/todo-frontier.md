# TODO frontier

Live worklist for the fleet — the things that are known-incomplete, deferred, or
parked mid-stream. Each item says **what**, **why it's not done**, and the
**next concrete step**. Close an item by folding it into the relevant chapter and
deleting it here.

## Observability / data platform

### ClickHouse deployment (+ Keeper ensemble, Prometheus migration)

**What.** A production-rehearsal ClickHouse platform: server on watchtower
(S3 disk → R2, `reconstructible`), a **3-node Keeper ensemble** on
ultraviolence / guccimane / shimmer (coordination plane, deliberately **not**
co-located with the server, deliberately **multi-arch** — shimmer is aarch64),
and a staged migration of the existing Prometheus/Grafana monitoring onto
ClickHouse. Full design: [ClickHouse production architecture](./infrastructure/clickhouse.md).

**Why it matters.** Dress rehearsal for heavy-metal production at scale —
separate Keeper plane, replicated engines + `ON CLUSTER` DDL from day one, S3
tiering. "Get good at Keeper" before it's load-bearing.

**Next step (Stage 1).** Adapt the working prior-art Keeper module
(`~/src/straylight/straylight-infra/nix/nixos/services/clickhouse-keeper.nix` —
index-derived `server_id`, `genNodesCfg` XML generators, unique/odd/≥3 assertions,
kazoo smoke test) into `modules/nixos/clickhouse.nix` under
`hyper-modern-nixos.databases.clickhouse.keeper`. **Diverge** from the prior art by
dropping its co-located `services.clickhouse` (our Keeper is *not* next to the
server) and sourcing the `nodes` list from a `clickhouse-keeper` service tag in
`registry/hosts.dhall`. Stand up all three, prove quorum + run the resilience
drills (one-node-loss survives, two-node-loss halts, rejoin recovers) before
touching the server half.

**Later (viz Phase 2).** Package **ClickStack / HyperDX** — not in nixpkgs, and
needs a MongoDB for app state. Likely a `dockerTools`/OCI image served from the
[zot registry](./services/registry.md) + a `hyper-modern-nixos` module + small
MongoDB, fronted by nginx. The OTel→ClickHouse spine is identical whether the UI is
Grafana (Phase 1) or HyperDX, so this slots on later with no re-instrumentation.

### Observability: OTel collector spine

**What.** Replace the scrape/forward model with `opentelemetry-collector-contrib`
(0.151 in nixpkgs; stable `clickhouse` exporter): one host collector per node
(prometheus + journald/filelog + OTLP receivers) → a central collector on
watchtower exporting to ClickHouse. The single ingestion spine for
metrics+logs+traces.

**Why.** OTel is good now (the old "it sucks" is dated); OTLP is the lingua franca
and it feeds both Grafana and HyperDX off the same pipeline.

**Next step.** Stand it up dual-running alongside the existing Prometheus/VM stack
once the ClickHouse server (Stage 2) is healthy; validate in Grafana before cutover.

## Networking

### Browser-only egress proxy over hard WireGuard

**What.** Stand up a dedicated WireGuard tunnel (e.g. Mullvad/own endpoint) and
route **only browser traffic** through it — a SOCKS/HTTP proxy or a
network-namespace–scoped WireGuard interface — rather than a Tailscale exit node.

**Why now.** The Tailscale exit node (Mullvad Miami) on `ultraviolence` captured
*all* public egress, including atticd's R2 fetches. Large chunked NAR reassembly
stalled over that tunnel → partial NARs → `Transferred a partial file` and broken
builds (see the [attic](./infrastructure/attic.md) read path / R2 slow tier). We
dropped the exit node to unblock builds; browser anonymity still wants *a* tunnel,
just not one that hijacks system/service egress.

**Constraint.** The proxy must be **scoped to the browser** so it never touches:
- atticd ↔ R2 (`*.r2.cloudflarestorage.com`),
- nativelink ↔ R2 / the tailnet RE fleet,
- restic ↔ R2, postgres ↔ `watchtower`, and other service egress.

**Candidate shapes (pick one when we revisit):**
- `wg-quick` interface in a dedicated **netns**, launch the browser inside it
  (clean kernel-level split; no app config needed).
- WireGuard endpoint + local **SOCKS5** (browser points at it; everything else
  stays on the WAN). Simplest app-scoped option.
- Keep the Tailscale exit node but add **`--exit-node-allow-lan-access`** plus
  explicit `--accept-routes` carve-outs — rejected for now: still routes service
  egress through Mullvad, which is exactly the failure we hit.

**Next step.** Prototype the netns + `wg-quick` approach on `ultraviolence`,
confirm `ip route get <r2-ip>` still resolves to the WAN gateway (not the tunnel)
while the browser's traffic exits via WireGuard.

## Media

The [media stack](./media/overview.md) is live on guccimane; these are the
parked edges.

### Dropbox: graduate to truly-public DNS

**What.** [Dropbox](./media/dropbox.md) is staged **tailnet-only** (nginx at
`drop.sju1.s4.gl`, autoindex off). The "secret-gist" model wants *public*
reachability for sharing with people off the tailnet.

**Why parked.** Going public is either (a) R2 public access + the bucket's
`r2.dev` URL, or (b) an R2 custom domain — both need a Cloudflare API token with
`Workers R2 Storage:Edit` (the R2 S3 creds we have are data-plane only), and a
custom domain additionally needs `s4.gl` (on Njalla) delegated to Cloudflare.
Deferred to do "all at once" with the broader public-DNS / cloudflared-edge
cutover.

**Next step.** When the public-edge layer lands, enable R2 public access via the
CF token, read back the public hostname, set `hyper-modern-nixos.dropbox.domain`,
switch guccimane.

### queuedrop: deploy the real queue endpoint

**What.** The [queuedrop](./media/queuedrop.md) extension builds and is
smoke-tested against `server/stub.py`. The stub just echoes — the real handler
should call Pinchflat's `Sources.create_source` or drive the
[library pipeline](./media/pipeline.md).

**Next step.** Package the queue endpoint as a `hyper-modern-nixos` service
(tailnet-only, like searxng), point it at Pinchflat, repoint the extension's
default endpoint, and do a live load-unpacked browser test (couldn't drive a GUI
browser from the build host).

### Pipeline → first-class (optional)

**What.** `media/pipeline/` is run-by-hand. Could become a flake app
(`nix run .#media-organize`) or wire into Pinchflat's lifecycle-script hook so
downloads are auto-tagged on arrival.

**Next step.** Decide if hands-on is fine (it is, for now) or wrap it; if wrapped,
the enrich/tag stages need `yt-dlp` + `python3Packages.mutagen` in the app's
`runtimeInputs`.

### Fleet activation tails

- **weyl** picks up the attic prefetch fix (and everything else on main) on its
  next `nixos-rebuild switch` — it was unreachable during rollout.
- **shimmer** is on the patched atticd, but its `nvidia-persistenced.service` has
  been failing since 2026-06-19 (pre-existing driver/kernel mismatch surfaced by
  the nixpkgs bump) — belongs to the NVIDIA/driver workstream, not media.
