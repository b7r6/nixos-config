# Deploying a host

How to push a NixOS closure to a machine in the fleet. The flake exposes one `nixosConfiguration`
per entry in the `hosts` table of `configurations/default.nix`: `ultraviolence`, `watchtower`,
`weyl`, `guccimane`, `shannon`, `shimmer` (aarch64), and `test-vm`.

## TL;DR

```bash
# the local box (ultraviolence) — switch in place
nixos-rebuild switch --flake .#ultraviolence

# a remote box over the tailnet — build locally first, then push
nixos-rebuild build  --flake .#watchtower                       # eval + build, no activate
nixos-rebuild switch --flake .#watchtower \
  --target-host watchtower --use-remote-sudo
```

## The proven remote pattern

Build the closure **locally first**, then activate it on the target. Building locally means the
build host realises from the [attic cache](../infrastructure/attic.md) (cache hit on most paths) and
only the diff is copied to the target over the tailnet:

```bash
# 1. eval + build locally (cache hit; nothing activates)
nixos-rebuild build --flake .#watchtower

# 2. activate on the remote, copying the closure over the tailnet.
#    --use-remote-sudo: run activation under sudo on the target so you SSH in
#    as your normal user, not root.
nixos-rebuild switch --flake .#watchtower \
  --target-host watchtower \
  --use-remote-sudo
```

`--target-host watchtower` resolves over MagicDNS — the box must be on the tailnet. Declarative
Tailscale enrollment (below, and [Tailscale](../infrastructure/tailscale.md)) is what keeps it
reachable across a rebuild that restarts `tailscaled`.

For the local machine you don't need `--target-host`:

```bash
nixos-rebuild switch --flake .#ultraviolence
```

## Devshell commands

`devshell.toml` wraps the everyday operations (`nix develop` / direnv to enter — see
[Dev shells](./dev-shells.md)). These use [`nh`](https://github.com/viperML/nh):

| Command | Runs | Purpose | | ------------- | ------------------ |
---------------------------------------------- | | `switch-os` | `nh os switch .` | Build + switch
the current host's NixOS config | | `switch-home` | `nh home switch .` | Build + switch the
standalone home config | | `treefmt` | `nix fmt` | Format the tree |

`nh os switch .` is the local equivalent of `nixos-rebuild switch --flake .#<thishost>` with a nicer
closure diff.

## Dry-run safety

Always preview what will change before you `switch`, especially on remote infra:

```bash
# realise the closure but DON'T activate it (safe; just builds)
nixos-rebuild build --flake .#watchtower

# build, then show what activating WOULD start/stop/restart — no changes made
nixos-rebuild dry-activate --flake .#watchtower \
  --target-host watchtower --use-remote-sudo
```

`dry-activate` prints the systemd units that would be (re)started and the config generation diff
without touching the running system. Use it before flipping infra switches on `watchtower`.

## Staged rollout (watchtower)

`watchtower` carries the fleet's stateful infra: the shared
[PostgreSQL](../infrastructure/postgres.md), the monolithic [`atticd`](../infrastructure/attic.md),
and [restic backups](../infrastructure/backups.md). It is brought up **incrementally** using local
boolean flags in `configurations/nixos/watchtower/configuration.nix`:

```nix
enableInfra  = true;   # postgres + monolithic atticd (the fleet cache backend)
enableBackup = false;  # restic timer (only after the by-hand `restic init`)
```

The pattern:

1. **Baseline deploy** — both flags `false`. Brings up only the safe baseline: declarative Tailscale
   enrollment + SSH. Confirm the box comes up healthy and stays reachable on the tailnet.
2. Flip `enableInfra = true`, rebuild, verify postgres + atticd are healthy. This also re-enables
   `watchtower`'s firewall (`hyper-modern-nixos.network.firewall.enable`) so the postgres
   `tailscale0`-scoped 5432 rule actually bites — the rest of the fleet runs firewall-off.
3. Do the [restic first backup by hand](./runbooks.md#b--restic-first-backup-by-hand), then flip
   `enableBackup = true`, rebuild.

Rebuild + verify **between each flip**. The `lib.mkIf enableInfra` / `lib.mkIf enableBackup` guards
gate both the `age.secrets` declarations and the service options, so a baseline deploy never
references secrets that aren't wired yet.

## Tailscale safety net

`watchtower` (and any remote box) sets:

```nix
hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
```

so if a rebuild restarts `tailscaled`, the node **re-auths from the key** rather than stranding
itself off the tailnet. See [Tailscale](../infrastructure/tailscale.md) and
[Adding a host](./adding-a-host.md) for wiring the key.
