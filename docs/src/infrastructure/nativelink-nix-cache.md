# Nix binary cache (nativelink)

A second cache, next to [attic](./attic.md): the **straylight NativeLink fork's Nix substituter**
(`nix_cache`), which serves the Nix HTTP binary-cache protocol backed by the NativeLink CAS instead
of attic's own chunk tables. Wired via `hyper-modern-nixos.nativelink.nixCache` in
`modules/flake/nativelink/nixos.nix`. **Off by default; currently live only on `guccimane`** as an
evaluation cache — it is not (yet) the fleet cache.

The point is to give the substituter a real workout. `guccimane` builds the per-platform static LLVM
toolchains, so every path it builds is pushed into this cache over loopback — a steady stream of
large NARs to exercise ingest, dedup, eviction, and the serve path under load. attic keeps running
unchanged; this rides alongside it.

## Why a second cache at all

attic and this are the same *protocol* (a Nix binary cache) over different *storage*. attic invented
its own machinery — content-defined chunk tables in postgres + an R2 object store, a bespoke garbage
collector. The NativeLink substituter instead reuses the CAS primitives NativeLink already has:

- **NARs** are digest-keyed CAS blobs (`sha256(nar)`), wrapped in `verify` so a corrupt or truncated
  upload is rejected at write time.
- **Path-info records** (the `.narinfo` metadata) are REv2 `ActionResult` envelopes behind a
  `completeness_checking` store, so an evicted NAR reads as a clean **404 miss** rather than a
  dangling narinfo — garbage collection is just eviction plus a reachability check, not a bespoke
  sweep.
- **Compression fidelity**: a `nix copy` push is stored *and served back* under its original
  compression (`preserve_upload_compression`, on by default), so pushing then pulling the same path
  works within Nix's narinfo TTL — attic/harmonia/nix-serve parity.

The strategic upside (not exploited yet on `guccimane`): the substituter's NAR store can be the
**same** CAS the RE services use, so Nix NARs and Bazel/REv2 blobs share one content-addressed store.
Here they are kept separate for isolation while the substituter earns trust.

## Deployment: an independent instance

This is **not** part of the [Dhall RE fleet](./nativelink-production.md). It is a separate `systemd`
service (`nativelink-nix-cache`) running a second `nativelink` process with its own trivial config —
three stores and one service — generated in Nix (no Dhall). On `guccimane` it runs beside the RE CAS
shard/worker and `atticd`:

```
guccimane  (one host, three peers on the tailnet)
  ├─ nativelink RE      :50051/:50052/:50061   CAS shard + x86_64 worker (Dhall fleet)
  ├─ atticd (replica)   :8080                  fleet binary cache
  └─ nativelink nix     :50071                  THIS — /nix/main, CAS-backed substituter
       NIX_NAR_STORE          verify → filesystem              (digest-keyed NAR blobs)
       NIX_PATH_INFO_STORE    completeness_checking → filesystem  (narinfo; evicted NAR ⇒ 404)
       NIX_ALIAS_STORE        filesystem                       (client URL name → digest)
```

Cache root: `http://guccimane:50071/nix/main`, tailnet-only.

### The fork input

The substituter service is upstream-absent, so `nixCache` pulls its binary from a **separate** flake
input — the straylight fork — rather than the upstream `nativelink` input the RE fleet uses:

```nix
# flake.nix
nativelink-nix.url = "git+https://git.s4.gl/straylight/straylight-nativelink?ref=b7r6/nativelink-nix";
nativelink-nix.inputs.nixpkgs.follows = "nixpkgs";
```

It is a strict superset of upstream, kept separate on purpose: standing up the Nix cache on one host
must not rebuild the RE fleet's `nativelink`. Only the host that enables `nixCache` builds the fork.

## Enabling it

```nix
# configurations/nixos/guccimane/configuration.nix
hyper-modern-nixos.nativelink = {
  enable = true;            # the RE CAS shard + worker (Dhall fleet)
  dhallHost = "guccimane";
  # …r2, openFirewall…

  # The Nix substituter, alongside attic. pushLocalBuilds copies every path this
  # box builds into it over loopback — the workout.
  nixCache = {
    enable = true;
    pushLocalBuilds = true;
  };
};
```

Key options (`hyper-modern-nixos.nativelink.nixCache`):

| Option | Default | Meaning |
| --- | --- | --- |
| `enable` | `false` | Run the substituter instance. |
| `listen` | `0.0.0.0:50071` | HTTP listener; cache root is `/nix/<instanceName>`. |
| `stateDir` | `/var/lib/nativelink-nix-cache` | NAR / path-info / alias filesystem stores. |
| `maxNarBytes` | 200 GiB | Eviction cap on the NAR store. Raise on a big builder. |
| `signingKeyFile` | `null` | `nix key generate-secret` key (agenix path). `null` ⇒ unsigned. |
| `pushLocalBuilds` | `false` | Install a loopback post-build-hook that pushes this host's builds. |
| `trustedInterfaces` / `openFirewall` | `[tailscale0]` / `true` | Bind all interfaces, open the port only on the tailnet. |

## The workout: `pushLocalBuilds`

With `pushLocalBuilds = true`, the module sets a Nix `post-build-hook` that runs after every build
and `nix copy`s the outputs to `http://127.0.0.1:50071/nix/main`. It is **non-fatal** — a cache
hiccup logs and returns `0`, so it can never fail a build. Over loopback the copy is fast, so the
latency it adds to each build's finalize is small even for multi-GiB toolchain NARs.

This is the deliberate difference from attic's `watch-store` (an async daemon): here it is a
synchronous post-build-hook, which is fine for a single-host evaluation cache and keeps the moving
parts to one systemd service. Nothing else on the fleet sets `post-build-hook`, so there is no
conflict with attic (which auto-pushes via `watch-store`).

## Signing and using it as a substituter

On `guccimane` the cache is **unsigned** — sufficient for the workout, since pushing never needs
signatures. To *pull* from it:

- **Quick/tailnet-internal**: clients set `require-sigs = false` for it.
- **Signed**: generate a key, store it via [agenix](./secrets.md), and set `signingKeyFile`. The
  server then signs every narinfo; clients trust the matching public key and wire it as a substituter
  the way [attic's `clientCache`](./attic.md) does (prepend to `substituters`, add to
  `trusted-public-keys`).

```sh
nix key generate-secret --key-name nativelink-nix-cache-guccimane-1 > key   # → agenix; set signingKeyFile
nix key convert-secret-to-public < key                                       # → clients' trusted-public-keys
```

## Firewall

The instance binds `0.0.0.0:50071` but the port is opened **only** on `trustedInterfaces`
(`tailscale0`), so the cache is tailnet-reachable, never internet-exposed — the same posture as attic
and the RE endpoint.

## Validating a config offline

The fork's binary carries `nativelink --check <config>`, which parses a config and resolves every
store/scheduler reference (catching a mistyped store name) **without** binding a socket, touching a
backend, or creating a directory. The module-rendered config passes it; a CI or pre-deploy gate can
run it against the generated JSON.

> Build note: like the RE `nativelink`, the fork is not in nixpkgs and builds ~640 derivations from
> source, and it is **not** in `nativelink.cachix.org` (it is our branch). The first `nixos-rebuild`
> on `guccimane` builds it there — fine, since `guccimane` is a builder, but expect a long first
> switch.

## Status

Single-host, unsigned, push-only evaluation cache. It is **not** a fleet substituter and does not
replace [attic](./attic.md) — attic remains the shared, signed, R2-backed cache every host pulls
from. The open questions this deployment answers: does the CAS-backed serve path hold up under the
LLVM-toolchain NAR firehose, and is the storage/dedup behavior worth graduating it to a fleet role
(shared CAS with the RE services, signed, wired as a substituter). Until then it rides alongside.
