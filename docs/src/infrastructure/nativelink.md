# Remote execution (nativelink)

[NativeLink](https://github.com/TraceMachina/nativelink) remote-execution / remote-cache
(Bazel/Buck2 RE), from `modules/nixos/nativelink.nix` under `hyper-modern-nixos.nativelink`. **Off
by default**, R2-backed CAS. This is the **least-mature** piece of the infra.

There is no upstream NixOS module, so this is a hand-rolled `systemd` service around the
`nativelink` binary from the flake input (it takes a single JSON5 config path). The module generates
that config from the host's `role`.

## Current state: single-box monolithic on `ultraviolence`

Today it's a single-box `monolithic` bringup: CAS + scheduler + a local x86_64 worker, all on one
host, with the CAS/AC stores backed by R2 (local fast tier + R2 slow tier) and TLS terminated at the
listener via a Tailscale-issued cert.

```nix
# configurations/nixos/ultraviolence/configuration.nix
age.secrets.nativelink-r2-env.file = …/nativelink-r2-env.age;

hyper-modern-nixos.nativelink = {
  enable = true;
  role = "monolithic";
  publicListen    = "0.0.0.0:50051";    # firewall opens it only on tailscale0
  workerApiListen = "127.0.0.1:50061";  # private backend, loopback
  workerApiEndpoint = "grpc://127.0.0.1:50061";
  openFirewall = true;
  tls = {
    enable = true;
    tailscale = { enable = true; domain = "ultraviolence.osiris-walleye.ts.net"; };
  };
  r2 = {
    enable = true;
    accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
    bucket = "straylight-nativelink-cas";
    environmentFile = "/run/agenix/nativelink-r2-env";  # R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
  };
  localCacheBytes  = 68719476736;  # 64 GiB local NVMe fast tier
  memoryCacheBytes = 8589934592;   # 8 GiB memory index
};
```

The intended multi-arch topology (not yet stood up): split the aarch64 worker out to `shimmer` (DGX)
with `role = "worker"` dialing this host's `worker_api` over the tailnet. Remote execution runs
**native** binaries, so you need one native worker per architecture.

| `role` | What runs |
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

`publicListen` binds all interfaces but `openFirewall` opens the public (50051) and `worker_api`
(50061) ports **only** on `trustedInterfaces` (`tailscale0`) — tailnet-only, never internet-exposed.
TLS terminates at the public listener; a `oneshot` + daily timer (`nativelink-tls-cert`)
provisions/renews a real Tailscale cert for the node's MagicDNS name, so tailnet clients connect
over `grpcs://` (`tls=true`) with no custom CA.

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
