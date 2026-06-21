# Tailscale

The tailnet is the fleet's spine: every inter-host service (postgres, attic,
nativelink) is reachable over `tailscale0` and **only** over `tailscale0`.
Configured by `modules/nixos/network.nix` under
`hyper-modern-nixos.network.tailscale.*` (adapted from `straylight-infra`'s
`fxy.services.tailscale`).

Tailnet domain: **`osiris-walleye.ts.net`** (MagicDNS). Set via
`hyper-modern-nixos.network.tailnet.domain`.

## The safety net: declarative enrollment

The headline precaution is **declarative auth-key enrollment**. When a host has
the auth-key agenix secret wired (`authKeyFile` set), `tailscaled` enrolls
non-interactively on first boot — a rebuild/reinstall **can't strand a remote
box** off the tailnet waiting for a manual `tailscale up`.

```nix
# configurations/nixos/<host>/configuration.nix
age.secrets.tailscale-auth-key.file =
  ../../../secrets/agenix/machines/tailscale-auth-key.age;

hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
```

Hosts **without** the secret keep working exactly as before (manual
enrollment), so this is non-breaking. `watchtower` enables it unconditionally
precisely because it is remote — see
`configurations/nixos/watchtower/configuration.nix`.

Use a **reusable, pre-authorized** key (ideally tagged, `ephemeral=false`) from
the Tailscale admin console. The secret is [`tailscale-auth-key`](./secrets.md).

## Option surface

All under `hyper-modern-nixos.network.tailscale`:

| Option | Type / default | Effect |
|---|---|---|
| `authKeyFile` | path, `null` | declarative enrollment (an agenix runtime path, never the store) |
| `acceptRoutes` | bool, `true` | `--accept-routes` — accept subnet routes from other nodes |
| `acceptDNS` | bool, `true` | `--accept-dns` — accept MagicDNS / tailnet DNS |
| `advertiseRoutes` | list, `[ ]` | `--advertise-routes=…` — be a subnet router |
| `advertiseExitNode` | bool, `false` | `--advertise-exit-node` |
| `acceptExitNode` | bool, `false` | `--exit-node-allow-lan-access` |
| `advertiseConnector` | bool, `false` | `--advertise-connector` — be an app connector |
| `sshAdvertise` | bool, `true` | advertise Tailscale SSH (`--ssh=false` when off) |
| `tags` | list, `[ ]` | `--advertise-tags=…` (must be authorized by the tailnet ACL) |
| `hostname` | str, `null` | `--hostname=…` override the registered name |
| `encryptState` | bool, `false` | TPM-encrypt the `tailscaled` state file |

`encryptState` is **off** by default: our boxes are reflashed often, where a TPM
can enter DA-lockout and crash-loop `tailscaled` (per straylight's note). When
off, the module passes `--encrypt-state=false`. Turn it on only for stable
servers with a healthy TPM.

## Routing features auto-detected

```nix
routes = ts.advertiseRoutes != [ ] || ts.advertiseExitNode;
services.tailscale.useRoutingFeatures = if routes then "both" else "client";
```

`useRoutingFeatures` is `"both"` **only when the node actually routes** (it
advertises routes or an exit node); otherwise it's a plain `"client"`. This
avoids forcing routing features and IP-forwarding onto workstations that don't
need them. Correspondingly, the IP-forwarding sysctls are only set when the node
routes:

```nix
boot.kernel.sysctl = mkIf routes {
  "net.ipv4.ip_forward" = 1;
  "net.ipv6.conf.all.forwarding" = 1;
};
```

## Throughput tuning (`tailscale-ethtool`)

A `oneshot` systemd unit (`tailscale-ethtool`) tunes the default NIC's offloads
after `network-online.target`. UDP GRO forwarding materially improves WireGuard
throughput on many drivers (straylight):

```sh
NETDEV=$(ip -o route get 8.8.8.8 | cut -f5 -d' ')
ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
```

## Firewall posture

`services.tailscale.openFirewall = true` and `tailscale0` is a
`trustedInterface` (all traffic on it allowed). Public ports are minimal: TCP
`22` and `3000`, UDP `41641` (the Tailscale endpoint), with
`checkReversePath = "loose"`.

Per-service, interface-scoped ports merge in cleanly on top — e.g.
[postgres](./postgres.md) opens `5432` only on `tailscale0`, and
[attic](./attic.md)/[nativelink](./nativelink.md) open their gRPC/HTTP ports
only on the trusted interfaces. The fleet otherwise runs firewall-off; the DB
host re-enables its firewall so those interface-scoped rules bite.
