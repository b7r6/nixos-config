# The fleet

The live machines, from `secrets/keys.nix` (the authoritative recipient list) and
`configurations/nixos/`. Tailnet domain is `osiris-walleye.ts.net`.

## Live hosts

| Host | Arch | Kind | Role | | --- | --- | --- | --- | | `ultraviolence` | x86_64 | NixOS | primary
workstation / infra host; attic **replica**; nativelink monolithic | | `watchtower` | x86_64 | NixOS
| central services: shared postgres + monolithic attic backend + the single GC | | `weyl` | x86_64 |
NixOS | nvidia workstation | | `guccimane` | x86_64 | NixOS | nvidia workstation | | `shimmer` |
aarch64 | NixOS | DGX Spark (GB10); uses `disko` + the `dgx-spark` module | | `shannon` | x86_64 |
NixOS | laptop, frequently powered down (still fleet) | | `gossamer` | aarch64 | DGX OS | **not** a
`nixosConfiguration`; global Nix; attic client / build node | | `test-vm` | aarch64\* | NixOS |
wayland-module test VM; imports only `self.nixosModules.wayland` |

\* `test-vm` defaults to `aarch64-linux` (`mkDefault`) for Apple-Silicon dev.

Only the seven NixOS hosts appear in the `hosts` table in
[`configurations/default.nix`](./flake-structure.md) and thus in `nixosConfigurations`. `gossamer`
is recorded in `secrets/keys.nix` only — it runs DGX OS with a global Nix install and is not managed
by this flake, but its host key is listed so it can receive secrets and act as an attic client /
build node.

## Roles in detail

### ultraviolence (x86_64, primary)

`configurations/nixos/ultraviolence/configuration.nix`. The daily-driver workstation and the place
new infra is proven first:

- attic **replica** — `hyper-modern-nixos.attic-node.profile = "replica"`, api-server against
  watchtower's postgres over the tailnet, sharing the R2 chunk store. See
  [attic](../infrastructure/attic.md).
- nativelink **monolithic** — CAS + scheduler + local x86_64 worker, R2-backed, TLS terminated with
  a Tailscale-issued cert. See [nativelink](../infrastructure/nativelink.md).
- restic → R2 backups, declarative Tailscale enrollment, Hyprland (`hyper-wayland`), nvidia. (The R2
  `rcloneMount` is now fleet-wide — see [the rclone mount note](#fleet-wide-r2-mounts) — not an
  ultraviolence distinguishing feature.)

### watchtower (x86_64, central services)

`configurations/nixos/watchtower/configuration.nix`. The fleet backend, rolled out incrementally via
local `enableInfra` / `enableBackup` switches:

- `hyper-modern-nixos.attic-node.profile = "monolithic-shared"` — hosts the shared postgres
  (`atticd` role+db, tailnet-reachable) **and** the monolithic atticd that runs migrations, serves,
  and the single garbage collector. Exactly one such node. See
  [postgres](../infrastructure/postgres.md) and [attic](../infrastructure/attic.md).
- The postgres module's interface-scoped `5432`-on-`tailscale0` rule takes effect because the
  firewall is on fleet-wide (default `true`) — watchtower inherits the fleet-on default, no special
  opt-in.
- restic → R2 (per-host repo `…/backups-restic/watchtower`), gated on `enableBackup`.

### weyl, guccimane (x86_64 workstations)

Straightforward nvidia desktops. `guccimane` runs `hyper-wayland`; `weyl` enables
`programs.hyprland` directly and pins a couple of `networking.hosts` entries. Both import
`hardware-configuration.nix` + the agenix module.

### shimmer (aarch64, DGX Spark)

`configurations/nixos/shimmer/`. The GB10 DGX Spark. Its `default.nix` imports
`disko.nixosModules.disko` + a `disko.nix`, the `dgx-spark` subtree (`self.nixosModules.default`
pulls it in), and forces `nixpkgs.hostPlatform = "aarch64-linux"`.

### shannon (x86_64 laptop)

`configurations/nixos/shannon/`. Laptop, often off — its host-key slot in `secrets/keys.nix` is
intentionally empty with a TODO to `ssh-keyscan` it on the next boot, so it can't yet decrypt
host-scoped secrets. Runs nvidia + `hyper-wayland`, with `mkForce`'d crisp-pixel font settings.

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
