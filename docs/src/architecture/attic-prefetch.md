# attic: NAR chunk-prefetch fix (the fleet-cache "hang")

## Symptom

A cold ~2.5 GB `nixos-rebuild switch` against the fleet attic cache (R2-backed)
crawled — appeared hung. The cache is on the critical path (this fleet mostly
serves paths NOT in upstream: aarch64, CUDA, custom builds), so this was
high-priority.

## What it was NOT

Ruled out by measurement:

- **Postgres / metadata** — narinfo lookups were 1–3 ms (DB on watchtower is
  healthy; a brief 09:27 window of `ts.net` resolution failure during the
  CoreDNS cutover recovered on its own).
- **R2 connectivity** — a raw HTTPS HEAD to the R2 endpoint connected in ~42 ms;
  a single whole (unchunked) NAR served in ~46 ms.
- **Substituter priority** — attic is correctly `priority=10` (preferred); we do
  NOT hide it behind cache.nixos.org, because it is the source of truth for most
  of what we pull.

## Root cause (read in the source, github:zhaofengli/attic)

`server/src/api/binary_cache.rs::get_nar` reassembles a chunked NAR via
`merge_chunks(chunks, streamer, storage, 2)` — a **hardcoded prefetch depth of
2**, with the author's own `// TODO: Make num_prefetch configurable`.

`merge_chunks` (`attic/src/io/mod.rs`) drains each chunk fully before topping the
prefetch queue back to `num_prefetch`. With depth 2 and the default 64 KiB
chunks against R2 (~150 ms/GET), the chunks effectively serialize: a tiny chunk
drains in microseconds, then the stream stalls on the next GET. An N-chunk NAR
costs ~N serial round-trips.

Measured on guccimane→R2 (unpatched, depth 2):

| NAR size | chunks (~size/64KiB) | time |
|----------|----------------------|------|
| 60 KiB   | 1 (whole)            | ~46 ms |
| 200 KiB  | ~3                   | ~0.53 s |
| 1 MiB    | ~15                  | ~1.3 s |
| 10 MiB   | ~150                 | ~22 s (extrapolated) |

Perfectly linear in chunk count ⇒ serial fetches. That is the "hang".

## Fix (github:sensenet-ai/attic, branch b7r6/nar-prefetch-concurrency)

Make the prefetch depth configurable: add `ChunkingConfig::nar_prefetch`
(config key `chunking.nar-prefetch`, serde-defaulted to 16 for back-compat) and
pass it to `merge_chunks` in `get_nar`. Deep enough prefetch overlaps the N GETs
into ~one round-trip.

Wired into the fleet:

- `flake.nix`: `attic` input → the fork branch; `attic.inputs.nixpkgs.follows`.
- `modules/nixos/nix.nix`: apply `inputs.attic.overlays.default` fleet-wide
  (provides the patched `pkgs.attic-server` / `attic-client`).
- `modules/nixos/attic.nix`: `chunking.narPrefetch` option → rendered as
  `chunking.nar-prefetch`. Chunk SIZES kept at upstream defaults (dedup-friendly)
  — the prefetch fix removes the latency penalty, so we don't sacrifice dedup.

## Results (guccimane→R2, warm)

| NAR size | depth 2 | depth 16 | depth 32 (current) |
|----------|---------|----------|--------------------|
| 1 MiB    | ~1.3 s  | ~0.34 s  | **~0.16 s** |
| 10 MiB   | ~22 s   | ~2.8 s   | **~1.0 s (10 MB/s)** |

At depth 32 the large-NAR case is transfer-bound (~10 MB/s = real R2 bandwidth),
not latency-bound — the serialization penalty is gone. 32 is the chosen default
(64 gives diminishing returns + more memory/connection pressure).

## Rollout

atticd hosts: watchtower (monolithic), guccimane, ultraviolence, shannon, weyl,
shimmer (aarch64). Deploy is a normal `nixos-rebuild switch`. weyl picks it up on
next switch (roaming); shimmer rebuilds the Rust crate natively (slow, aarch64).

Note: the `atticd-watch-store` client unit can lose one startup race on switch
(exit 4) and auto-restarts to `active` — cosmetic, not a server failure.

## Upstreaming

The change is minimal and matches upstream style; open a PR from
`sensenet-ai/attic:b7r6/nar-prefetch-concurrency` to `zhaofengli/attic`
(resolves the existing `num_prefetch` TODO).
