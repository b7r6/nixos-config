# Remote execution (nativelink)

[NativeLink](https://github.com/TraceMachina/nativelink) remote-execution / remote-cache
(Bazel/Buck2 RE), from `modules/nixos/nativelink.nix` under `hyper-modern-nixos.nativelink`. **Off
by default**, R2-backed CAS.

There is no upstream NixOS module, so this is a hand-rolled `systemd` service around the
`nativelink` binary from the flake input (it takes a single JSON5 config path). Live hosts get that
config from the typed **Dhall fleet** (`nativelink/`, rendered at eval time via IFD — no committed
JSON artifacts).

## Current state: 3-host Dhall fleet (scheduler@`watchtower`)

Today it's a Dhall-driven multi-arch fleet across `watchtower`, `guccimane`, and `ultraviolence`:
scheduler on `watchtower`, a weighted CAS shard ring (watchtower:4 / guccimane:4 / ultraviolence:1),
and an x86_64 worker on each. CAS/AC stores are R2-backed (local NVMe fast tier + shared R2 slow
tier). Workers dial the scheduler's `worker_api` over the tailnet at
`grpc://watchtower.sju1.s4.gl:50061`.

Each live host sets `dhallHost = "<host>"`, which makes the module render that host's config from
`nativelink/fleet.dhall` at eval time (IFD) and **ignore** the legacy `role`/entrypoint/TLS path.

```nix
# configurations/nixos/watchtower/configuration.nix (guccimane/ultraviolence mirror this)
age.secrets.nativelink-r2-env.file = …/nativelink-r2-env.age;

hyper-modern-nixos.nativelink = {
  enable = true;
  dhallHost = "watchtower";   # consume nativelink/out/watchtower.json; ignore legacy role
  openFirewall = true;        # firewall opens 50051/50052/50061 only on tailscale0
  r2 = {
    enable = true;
    accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
    bucket = "straylight-nativelink-cas";
    environmentFile = "/run/agenix/nativelink-r2-env";  # R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
  };
};
```

The x86_64 fleet is **live and connected**. The aarch64 half is deferred: `shimmer` (DGX) is the
intended aarch64 CAS shard + executor but is `enabled = False` in `fleet.dhall` (the nativelink flake's
LLVM 22 `compiler-rt` won't build for `aarch64-unknown-linux-musl` yet). Remote execution runs
**native** binaries, so an aarch64 action needs an aarch64 worker; that lands when shimmer is
re-enabled.

For the full production architecture — sharded CAS, DNS ownership, the OCI-toolchain plan, the
SBSA/aarch64 circle-back — see [NativeLink production architecture](./nativelink-production.md).

### Legacy `role` path (superseded)

The module still carries a legacy in-Nix generator that assembles a config from a host's `role`
(`monolithic`/`scheduler`/`worker`) with `publicListen`/`workerApiListen`/`workerApiEndpoint` and
TLS-at-the-listener (`tls.tailscale`) options. **No live host uses it** — every deployed host sets
`dhallHost`, which takes priority and ignores `role`. It is retained as a fallback (see
[production notes](./nativelink-production.md)) until the Dhall path is proven fleet-wide.

| `role` (legacy) | What runs |
| --- | --- |
| `monolithic` | CAS + scheduler + local worker (single x86_64 host) |
| `scheduler` | CAS + scheduler only (workers dial in) |
| `worker` | local worker only; dials `workerApiEndpoint` (use on aarch64) |

## Storage & secrets

CAS/AC stores become `fast_slow` when `r2.enable`: a local filesystem/memory fast tier in front of
R2 as the durable slow tier. `account_id`/`bucket` are non-secret; creds are read from
[`nativelink-r2-env`](./secrets.md) and injected via shellexpand (`${R2_ACCESS_KEY_ID}` /
`${R2_SECRET_ACCESS_KEY}`) so they never enter the store. With `r2.enable = false`, stores are local
filesystem only (`maxStoreBytes`).

## Network & TLS

Under the live Dhall fleet, every node binds on `0.0.0.0` but `openFirewall` opens the fixed fleet
ports — public (50051), CAS shard (50052), and `worker_api` (50061) — **only** on `trustedInterfaces`
(`tailscale0`), so the RE endpoint is tailnet-only, never internet-exposed. Traffic is plaintext over
the encrypted tailnet; there is no per-listener TLS in the rendered fleet config.

> The legacy `role` path additionally offered TLS-at-the-listener: a `oneshot` + daily timer
> (`nativelink-tls-cert`) provisioning/renewing a real Tailscale cert for the node's MagicDNS name so
> clients connect over `grpcs://` (`tls=true`). That path is superseded by `dhallHost` and unused by
> any live host.

## The toolchain / hermeticity problem

Standing up CAS + scheduler + worker (this module) is the easy part. Making remote **actions**
execute correctly is the hard part, and it is **not a server concern** — it lives in the **client**
(Buck2/Bazel) repo (see the module header):

- **Property matching** — the scheduler matches an action's requested platform properties against
  what a worker advertises (`workerProperties` + host-derived
  `cpu_arch`/`OSFamily`/`ISA`/`container-image`/`lre-rs`). Request a property no worker advertises →
  the action never schedules. This routes work; it does **not** make it reproducible.
- **Hermeticity** — a remote worker runs the action's command on **its** filesystem. The fix
  (NativeLink's LRE docs) is a content-addressed toolchain: every referenced tool is a
  `/nix/store/...` path. Because our workers are NixOS and share `/nix/store`, a Buck2 toolchain
  pointing at store binaries is hermetic **and** cache-shareable. FHS paths are not.

`instanceName` (default `main`) must match the client's `.buckconfig instance_name`. The module
ships a default per-action `entrypoint` wrapper that prepends a baseline nix-pinned toolchain
(coreutils/bash/findutils/sed/grep/awk) to `PATH` — the minimum to make non-LRE `genrule`/`sh`
actions run at all (remote actions run with **no** inherited `PATH`). It is **not** full
hermeticity; override via `workerEntrypoint`.

> Build note: NativeLink is not in nixpkgs and builds ~640+ derivations from source. Add
> `nativelink.cachix.org` to `nix.settings.substituters` before enabling on any host, or expect a
> very long first build.
