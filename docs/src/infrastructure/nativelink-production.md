# NativeLink production architecture (design)

> Status: **design**, implemented in stages. The current single-host `monolithic`
> deployment (see [nativelink](./nativelink.md)) is the starting point; this is
> where it goes: a real multi-arch build farm with a sharded CAS, separated
> scheduler/workers, OCI-toolchains-from-zot, and a **Dhall config layer** so a
> valid NativeLink config is a type-check, not a Rubik's cube.
>
> Grounded in: the NativeLink docs (architecture, production, LRE, persistent
> workers) and the working prior art in `~/src/straylight/straylight-prelude`
> (`nix/modules/flake/{nativelink,ociutils}`, `dhall/`).

## The four roles, deployed for real

NativeLink is four RE-API roles that scale independently
([docs](https://docs.nativelink.com/explanations/architecture)):

- **CAS** — content-addressed blob store; the *only* stateful role.
- **AC** — action cache (`hash(Action) → ActionResult`); disposable.
- **Scheduler** — stateless dispatcher; matches actions to workers by platform
  properties.
- **Workers** — stateless executors; fetch inputs from CAS, run the action,
  upload outputs.

Target fleet topology (single-site `sju1` today, multi-arch):

| host | arch | scheduler | CAS shard (weight) | worker |
| --- | --- | --- | --- | --- |
| watchtower | x86_64 | **yes** (the dispatcher) | yes (large) | yes |
| guccimane | x86_64 | — | yes (large) | yes |
| shimmer | aarch64 | — | yes (medium) | yes (the only aarch64 executor) |
| ultraviolence | x86_64 | — | **yes (small)** | yes |

Scheduler on watchtower; executors on all four. Multi-arch matters: remote
execution runs **native** binaries, so an aarch64 action must land on shimmer.
The scheduler's `cpu_arch`/`ISA` exact-match properties route this; the module
already derives them per host.

ultraviolence is in the CAS ring **deliberately small**: it's tight on disk, so it
carries a smaller slice. That's the point — a ring where every node is `weight = 1`
is a toy; weighting by real headroom is the production discipline (and good
practice for right-sizing the fleet). It also makes the CAS-≠-worker-topology
point concrete: ultraviolence is a heavy *worker* (nativelink host today) yet a
*small* CAS shard — the two roles size independently.

## Sharded CAS (stripe the load)

The bottleneck to avoid is funnelling every blob through watchtower's CAS. The
production model ([docs](https://docs.nativelink.com/configuration/production))
uses the **`shard` store**: a consistent-hash ring over backend stores, hashed by
blob digest, with per-shard **`weight`** for unevenly-sized nodes:

```json5
{ name: "CAS_MAIN_STORE",
  shard: { stores: [
    { store: { ref_store: { name: "CAS_watchtower"    } }, weight: 4 },
    { store: { ref_store: { name: "CAS_guccimane"     } }, weight: 4 },
    { store: { ref_store: { name: "CAS_shimmer"       } }, weight: 2 },
    { store: { ref_store: { name: "CAS_ultraviolence" } }, weight: 1 },  // tight on disk
  ] } }
```

Weights are illustrative (calibrate to actual free NVMe per node); ultraviolence's
`weight: 1` against the servers' `4` reflects its disk pressure. As disks change
or the fleet right-sizes, re-weighting is a one-line edit in the Dhall fleet config
— the ring rebalances by digest.

Key design point the docs make explicit: **CAS topology is separate from worker
topology.** The shard ring is its own tier; workers just point
`cas_fast_slow_store` at the composite `CAS_MAIN_STORE`. So we can weight the CAS
ring by node size independently of where executors run — exactly the "workers on a
different ring than the CAS nodes" intuition.

Each shard is a per-host store: a local NVMe **fast tier** fronting the shared R2
**slow tier** (`straylight-nativelink-cas`, the authoritative durable copy).
Because blobs are content-addressed, a blob is identical on every shard/host —
**no consistency problem**, R2 is the shared truth, local tiers are caches.

> Open (needs benching): on a single 2.5 Gb switch with R2 as the shared slow
> tier, does the sharded ring beat the simpler "each worker has a local fast tier
> over shared R2, scheduler keeps one logical CAS"? The shard ring earns its keep
> when one node's CAS bandwidth/capacity is the limit. We build the ring (it's the
> production shape and the ask), and bench it against the simpler model.

## worker_api over the tailnet

The scheduler's `worker_api` (currently loopback `:50061`) must be reachable by
remote workers. It binds the tailnet; workers dial the logical name CoreDNS now
serves: `grpc://watchtower.sju1.s4.gl:50061`. Plaintext over the encrypted
tailnet — it's the private backend, not the client-facing API.

## Toolchains as OCI images in zot (not nix-store)

The deliberate choice: **toolchains are OCI images, addressed by digest, served
from zot** (`registry.sju1.s4.gl`) — *not* shared `/nix/store` paths.

Why, on the merits (not just preference):

- NativeLink's `/nix/store`-as-toolchain model (LRE) assumes **every worker shares
  the exact same store paths** and that client+worker derive bit-identical paths.
  On a **multi-arch** fleet that's already false (aarch64 `clang` ≠ x86_64
  `clang`), and any nixpkgs-pin drift between client and worker silently breaks
  the action hash. "Same hash everywhere" only holds within an arch.
- An OCI image referenced by **`@sha256:` digest** is a stronger, self-contained
  contract: one immutable artifact, pulled by digest, identical on every
  arch-matched worker — no shared-filesystem coupling.
- The **Buck2 prelude is the source of truth for which toolchains exist** and can
  **assert each is present in the registry by digest** before emitting an action
  that requests it (`[buck2_re_client.platform_properties] container-image = …`,
  per the prior-art `buckconfig-re.dhall`). A real supply chain, not a coincidence
  of store paths.

How the worker *presents* the image — the prior art's key move (`ociutils/lib.nix`,
philosophy "**namespaces, not daemons**"):

- **Not** a Docker/podman daemon. The worker presents the image's filesystem into
  the build sandbox via **`bwrap` bind-mounts** (FHS presentation), optionally
  **Firecracker** for network-isolated builds. Lighter, daemonless, and already
  built in straylight-prelude.

Image *build* path (keep nix where it's good): `pkgs.dockerTools.streamLayeredImage`
packs a nix toolchain closure into a reproducible, content-addressed OCI image (no
Docker daemon) → push to zot → prelude references it by digest. Reproducible build,
digest-pinned runtime contract, zero shared-store coupling. (Plain Dockerfile
images work identically against the registry contract if a toolchain isn't nix.)

## The Dhall config layer (un-fuck-up the config)

NativeLink's JSON5 config is a footgun: `stores`/`schedulers` are **arrays of
named objects** (not maps — get it wrong and it's `invalid type: map`), the store
graph is a web of `ref_store` names that must resolve, and the property-match
modes (`exact`/`minimum`/`priority`) must agree across scheduler, worker, and
client. A typed **Dhall schema** turns all of that into an evaluation-time type
error, the same way `registry/` did for topology.

Plan (mirrors the prior-art `straylight-prelude/dhall/` structure):

- `nativelink/schema.dhall` — typed `Store`/`Scheduler`/`Worker`/`Server`/`Config`
  with the array-of-named-objects shape baked in, `ref_store` names as a checked
  enum where possible, property-match modes as a typed union.
- `nativelink/fleet.dhall` — the actual topology (scheduler@watchtower, the
  weighted CAS shard ring, the three workers, their platform properties) authored
  against the schema.
- A render to committed JSON (IFD-free, like the topology registry) consumed by
  the nixos module, which stops hand-generating JSON5 and instead validates +
  renders the Dhall.

## Build stages

1. **Dhall config layer** — schema + render that **reproduces the current working
   single-host config** byte-for-byte-equivalent. Prove the typed layer is sound
   before changing topology.
2. **Multi-arch + sharded CAS** — scheduler@watchtower, workers on all three,
   weighted shard ring, worker_api on the tailnet. Deploy, prove an action runs on
   each arch.
3. **OCI toolchains in zot** — `dockerTools` toolchain images → zot; worker bwrap
   presentation; prelude digest-verification. The hermeticity payoff.

Each stage lands and is proven before the next.
