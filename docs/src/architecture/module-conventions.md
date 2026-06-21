# Module conventions

Conventions shared by everything under `modules/nixos`.

## The `hyper-modern-nixos.*` namespace

Every module that this repo defines puts its options under a single namespace:

```nix
options.hyper-modern-nixos.<feature> = { ... };
```

Real examples, with their files:

| Option | File |
| --- | --- |
| `hyper-modern-nixos.network` | `modules/nixos/network.nix` |
| `hyper-modern-nixos.nvidia` / `.radeon` | `modules/nixos/{nvidia,radeon}.nix` |
| `hyper-modern-nixos.docker` / `.libvirt` | `modules/nixos/{docker,libvirt}.nix` |
| `hyper-modern-nixos.databases.postgres` | `modules/nixos/postgres.nix` |
| `hyper-modern-nixos.attic` | `modules/nixos/attic.nix` |
| `hyper-modern-nixos.attic-node` | `modules/nixos/attic-node.nix` |
| `hyper-modern-nixos.backup` | `modules/nixos/backup.nix` |
| `hyper-modern-nixos.nativelink` | `modules/nixos/nativelink.nix` |
| `hyper-modern-nixos.rcloneMount` | `modules/nixos/rclone-mount.nix` |
| `hyper-modern-nixos.users` | `modules/nixos/myusers.nix` |
| `hyper-modern-nixos.wayland` / `.hyper-wayland` | `modules/nixos/wayland` |

This makes "ours vs. upstream" obvious at a host call site, and keeps grep
honest.

## Option-gated, off by default

Each module wraps its `config` in `lib.mkIf cfg.enable`, where `enable` is an
`mkEnableOption` defaulting to `false`. A gated, disabled module contributes
nothing to the system closure, so it is safe to import all of them
unconditionally. That is exactly what the aggregator does:

```nix
# modules/nixos/default.nix
{ lib, ... }: {
  imports = [
    ./base.nix ./nix.nix ./packages.nix ./greetd.nix ./myusers.nix ./secrets.nix
    ./bluetooth.nix ./nvidia.nix ./radeon.nix ./usb.nix
    ./network.nix ./network-manager.nix
    ./docker.nix ./libvirt.nix
    ./postgres.nix ./backup.nix ./attic.nix ./attic-node.nix
    ./nativelink.nix ./rclone-mount.nix
    ./android.nix ./appimage.nix ./nix-ld.nix
    ./impermanence.nix ./impurity.nix ./xremap.nix
    ./dgx-spark ./wayland
  ];
}
```

`self.nixosModules.default` (= `../modules/nixos`) is this file. Because every
module is inert until enabled, a host config is "import the aggregator + set the
options you want" — there are **no per-host import lists**. Layout is flat: each
module is a sibling file (no `common/` or `services/` nesting).

A handful of always-on essentials don't gate (`base`, `nix`, `packages`,
`greetd`, `myusers`, `secrets`), plus a few fleet-wide defaults set directly in
the aggregator:

```nix
hyper-modern-nixos.network = {
  enable = true;
  tailnet.domain = "osiris-walleye.ts.net";
  firewall.enable = lib.mkDefault false;   # watchtower opts back in
  useBackupResolver = true;
};
hyper-modern-nixos.users.defaultAuthorizedKeys = [ "ssh-ed25519 …" /* b7r6 */ ];
```

`firewall.enable` is `mkDefault false` so a host that needs interface-scoped port
rules (e.g. [watchtower](./fleet.md)'s postgres) can flip it back on.

## The self-enabling role / profile pattern

Some modules are thin **profile selectors** that translate one high-level choice
into a coherent set of low-level options on the orthogonal axes, so a host
switches roles by changing a single enum.

The canonical example is `modules/nixos/attic-node.nix`. A host is just:

```nix
age.secrets.atticd-rs256.file     = …/atticd-rs256.age;
age.secrets.attic-push-token.file = …/attic-push-token.age;
hyper-modern-nixos.attic-node = { enable = true; profile = "replica"; };
```

The module derives `mode × database × storage` from `profile`:

- `standalone` — monolithic, self-contained (local sqlite/pg + local storage),
  no fleet dependency.
- `replica` — stateless `api-server` against the shared fleet postgres + R2.
- `monolithic-shared` — monolithic on the shared backend; runs migrations,
  serves, and the single GC. Exactly one node (watchtower) uses it.

Flipping `standalone ↔ replica` changes only mode/database/storage; the cache
identity (name, public key, push token) is constant, so there's no other churn.
The `monolithic-shared` branch even stands up the local shared postgres and
restores the cache signing keypair from agenix on activation. See
[attic](../infrastructure/attic.md).

Other modules in the same spirit: `hyper-modern-nixos.nativelink` (`role` =
`monolithic` | `worker` | …), and the `hyper-wayland` desktop bundle.

## Secrets: agenix runtime paths, never the store

Secrets are referenced by their **decrypted runtime path** under `/run/agenix`,
never inlined into the Nix store. The pattern at a host:

```nix
age.secrets.restic-password.file = …/secrets/agenix/machines/restic-password.age;

hyper-modern-nixos.backup = {
  enable = true;
  passwordFile = "/run/agenix/restic-password";   # runtime path
  environmentFile = "/run/agenix/restic-r2-env";   # env file w/ R2 creds + repo URL
};
```

Things that would leak into the world-readable store (R2 account ids, AWS keys,
postgres passwords, repo URLs) live **inside** the decrypted env file, not in
Nix expressions. Module option defaults reflect this — e.g.
`hyper-modern-nixos.attic-node.environmentFile` defaults to
`/run/agenix/atticd-rs256`, and `network.tailscale.authKeyFile` is documented as
"an agenix runtime path, never the store".

Recipient keys (who can decrypt what) are data in `secrets/keys.nix`; the
admin commands live in the `secrets` devshell. See
[secrets](../infrastructure/secrets.md).
