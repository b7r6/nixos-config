# The fleet

The live machines, from `secrets/keys.nix` (the authoritative recipient list) and
`configurations/nixos/`. The tailnet MagicDNS suffix lives once in
`hyper-modern-nixos.network.tailnet.domain` (see [Tailscale](../infrastructure/tailscale.md)).

## Live hosts

| Host | Arch | Kind | Role |
| --- | --- | --- | --- |
| `watchtower` | x86_64 | NixOS | central services: postgres, attic (monolithic-shared), supabase, nativelink (scheduler+CAS+worker), registry (zot), reverse-proxy (nginx), CoreDNS |
| `ultraviolence` | x86_64 | NixOS | primary workstation; attic replica, nativelink (CAS+worker), searxng+torrents, CoreDNS |
| `guccimane` | x86_64 | NixOS | nvidia workstation; nativelink (CAS+worker), media (pinchflat+navidrome+jellyfin), dropbox, CoreDNS |
| `shimmer` | aarch64 | NixOS | DGX Spark (GB10); attic client, CoreDNS; `disko` + `dgx-spark` module |
| `shannon` | x86_64 | NixOS | laptop (frequently off); attic client, backup |
| `weyl` | x86_64 | NixOS | nvidia workstation; attic client, backup |
| `gossamer` | aarch64 | DGX OS | **not** a `nixosConfiguration`; global Nix; attic client / build node |
| `test-vm` | x86_64\* | NixOS | wayland-module test VM; imports only `self.nixosModules.wayland` |

## Service → host matrix

| Service | watchtower | ultraviolence | guccimane | shimmer | shannon | weyl |
| --- | --- | --- | --- | --- | --- | --- |
| **attic** (cache) | monolithic-shared (the backend) | replica | client | client | client | client |
| **nativelink** (RE) | scheduler+CAS+worker | CAS+worker | CAS+worker | — (disabled) | — | — |
| **CoreDNS** (split-horizon) | ✓ (authoritative) | ✓ | ✓ | ✓ | — | — |
| **supabase** (full stack) | ✓ | — | — | — | — | — |
| **postgres** (shared DB) | ✓ (+ PITR to R2) | — | — | — | — | — |
| **registry** (OCI/zot) | ✓ | — | — | — | — | — |
| **reverse-proxy** (nginx) | ✓ (studio, registry) | — | ✓ (media) | — | — | — |
| **searxng + torrents** | — | ✓ | — | — | — | — |
| **media** (pinchflat etc.) | — | — | ✓ | — | — | — |
| **dropbox** (file sharing) | — | — | ✓ | — | — | — |
| **backup** (restic → R2) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| **rclone mount** (R2 FUSE) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

\* `test-vm` **builds** as `x86_64-linux`. Its host dir sets
`nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux"` (for Apple-Silicon dev), but `mkHost` in
`configurations/default.nix` injects `{ nixpkgs.hostPlatform = system; }` at regular priority with
`system` defaulting to `"x86_64-linux"`, which overrides the host dir's `mkDefault` (priority 1000).
The `mkDefault "aarch64-linux"` is therefore effectively dead — to actually build aarch64 you'd set
`test-vm.system = "aarch64-linux"` in the `hosts` attrset.

Only the seven NixOS hosts appear in the `hosts` table in
[`configurations/default.nix`](./flake-structure.md) and thus in `nixosConfigurations`. `gossamer`
is recorded in `secrets/keys.nix` only — it runs DGX OS with a global Nix install and is not managed
by this flake, but its host key is listed so it can receive secrets and act as an attic client /
build node.

## Roles in detail

### watchtower (x86_64, central services)

`configurations/nixos/watchtower/configuration.nix`. The fleet backend:

- **attic** (monolithic-shared) — hosts the shared postgres (`atticd` role+db,
  tailnet-reachable), the monolithic atticd (migrations + serve + single GC), and
  the cache signing keypair. See [postgres](../infrastructure/postgres.md) and
  [attic](../infrastructure/attic.md).
- **supabase** — the full self-hosted stack (9 containers via oci-containers), on
  its own postgres cluster. See [supabase](../services/supabase.md).
- **nativelink** — scheduler + CAS shard (weight 4) + x86_64 worker. The fleet's
  RE coordinator. See [nativelink](../infrastructure/nativelink.md).
- **registry** (zot) — OCI image registry, R2-backed. See [registry](../services/registry.md).
- **reverse-proxy** (nginx) — wildcard cert (`*.sju1.s4.gl` via DNS-01), fronts
  `studio.sju1.s4.gl` (supabase) and `registry.sju1.s4.gl` (zot).
- **CoreDNS** — authoritative for `sju1.s4.gl`, split-horizon resolver.
- restic → R2 backups, declarative Tailscale enrollment.

### ultraviolence (x86_64, primary workstation)

`configurations/nixos/ultraviolence/configuration.nix`. The daily-driver workstation:

- **attic** replica — api-server against watchtower's postgres, sharing the R2
  chunk store.
- **nativelink** — CAS shard (weight 1) + x86_64 worker, dialing watchtower's
  scheduler.
- **searxng + torrents** — private search + media acquisition.
- **CoreDNS** — split-horizon resolver (same zone as watchtower).
- Hyprland (`hyper-wayland`), nvidia, restic → R2.

### guccimane (x86_64, media + infra)

`configurations/nixos/guccimane/configuration.nix`. nvidia workstation + media server:

- **nativelink** — CAS shard (weight 4) + x86_64 worker.
- **media** — pinchflat (yt-dlp manager), navidrome, jellyfin. See [media](../media/overview.md).
- **dropbox** — shareable file URLs (`drop.s4.gl`).
- **reverse-proxy** (nginx) — fronts media services.
- **CoreDNS** — split-horizon resolver.
- Hyprland (`hyper-wayland`), nvidia, restic → R2.

### shimmer (aarch64, DGX Spark)

`configurations/nixos/shimmer/`. The GB10 DGX Spark:

- **attic** client + **CoreDNS** (split-horizon resolver).
- nativelink CAS shard (weight 2) — currently **disabled** (`enabled = False` in
  the Dhall fleet) pending the aarch64 worker bringup.
- `disko` + `dgx-spark` module. Forces `nixpkgs.hostPlatform = "aarch64-linux"`.
- restic → R2.

### shannon (x86_64, laptop)

`configurations/nixos/shannon/`. Laptop, often off:

- attic client, restic → R2, nvidia + `hyper-wayland`.
- No CoreDNS (roaming; uses the fleet resolver via Tailscale split-DNS when
  configured, else no `sju1.s4.gl` resolution).

### weyl (x86_64, workstation)

`configurations/nixos/weyl/`. nvidia workstation:

- attic client, restic → R2, Hyprland.
- No CoreDNS (same as shannon — laptop-class, no resolver).

### gossamer (aarch64, DGX OS — not NixOS)

Recorded in `secrets/keys.nix` only. Global Nix on DGX OS; consumes the
[attic](../infrastructure/attic.md) cache and can act as a build node. Never add it to the `hosts`
table.

### test-vm

`configurations/nixos/test-vm/`. A throwaway VM that imports **only** `self.nixosModules.wayland`
(not the full `default` aggregator) to iterate on the wayland module in isolation, with an inline
`test` user.

## Fleet-wide R2 mounts

Every host (via the `hyper-modern-nixos.rcloneMount` fleet default, on in
`modules/nixos/default.nix`) gets **two** rclone FUSE mounts off the `straylight-r2` remote's
`host-mount` bucket:

- `/mnt/r2/common` → `host-mount/common` — **shared** by the whole fleet.
- `/mnt/r2/<hostname>` → `host-mount/<host>` — this host's **isolated** subtree.

The per-host subtree is derived from `config.networking.hostName`, and the module **self-wires** the
`rclone-conf` agenix secret, so there is nothing per-host to configure — importing the default
module is enough. See [reference/options](../reference/options.md#rclone-mounts).

**Freshness:** rclone's dir cache is lazy (it LISTs the remote only on access, once the cached entry
is older than `--dir-cache-time`; R2 has no change-polling, so `--poll-interval` is inert). The
**common** mount uses a short `--dir-cache-time=5s` so a peer's write shows up within a few seconds
of the next `ls` — idle mounts issue no requests, and an R2 LIST is a near-free Class A op. The
**per-host** mount keeps `12h`: nothing else writes there, so its cache can never be stale.

## Decommissioned

Pruned from the fleet and **not** to be re-added without a real host (per the note in
`secrets/keys.nix`):

```
beratna  flatline  galois  noether  railgun  ultralight
```

## Adding / rotating host keys

`secrets/keys.nix` is data-only: `users` and `hosts` attrsets mapping a name to its ssh-ed25519
public keys (agenix takes SSH ed25519 keys directly). To enroll a host:

```sh
ssh <host> cat /etc/ssh/ssh_host_ed25519_key.pub   # authoritative
```

Add it under `hosts`, then rekey the secrets it should decrypt (`agenix -r` / the `rekey` command in
the `secrets` devshell). A host can only decrypt a secret once its key is listed **and** the secret
has been rekeyed to include it. See [secrets](../infrastructure/secrets.md).
