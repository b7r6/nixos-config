# Tailscale

The tailnet is the fleet's spine: every inter-host service (postgres, attic, nativelink) is
reachable over `tailscale0` and **only** over `tailscale0`. Configured by
`modules/nixos/network.nix` under `hyper-modern-nixos.network.tailscale.*` (adapted from
`straylight-infra`'s `fxy.services.tailscale`).

Tailnet domain: **`osiris-walleye.ts.net`** (MagicDNS). Set via
`hyper-modern-nixos.network.tailnet.domain`.

## The safety net: declarative enrollment

The headline precaution is **declarative auth-key enrollment**. When a host has the auth-key agenix
secret wired (`authKeyFile` set), `tailscaled` enrolls non-interactively on first boot — a
rebuild/reinstall **can't strand a remote box** off the tailnet waiting for a manual `tailscale up`.

```nix
# configurations/nixos/<host>/configuration.nix
age.secrets.tailscale-auth-key.file =
  ../../../secrets/agenix/machines/tailscale-auth-key.age;

hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
```

Hosts **without** the secret keep working exactly as before (manual enrollment), so this is
non-breaking. `watchtower` enables it unconditionally precisely because it is remote — see
`configurations/nixos/watchtower/configuration.nix`.

Use a **reusable, pre-authorized** key (ideally tagged, `ephemeral=false`) from the Tailscale admin
console. The secret is [`tailscale-auth-key`](./secrets.md).

## Option surface

All under `hyper-modern-nixos.network.tailscale`:

| Option | Type / default | Effect |
| --- | --- | --- |
| `authKeyFile` | path, `null` | declarative enrollment (an agenix runtime path, never the store) |
| `acceptRoutes` | bool, `true` | `--accept-routes` — accept subnet routes from other nodes |
| `acceptDNS` | bool, `true` | `--accept-dns` — accept MagicDNS / tailnet DNS |
| `advertiseRoutes` | list, `[ ]` | `--advertise-routes=…` — be a subnet router |
| `advertiseExitNode` | bool, `false` | `--advertise-exit-node` |
| `acceptExitNode` | bool, `false` | `--exit-node-allow-lan-access` |
| `exitNode` | str, `null` | route egress through this exit node, via a `tailscale set` oneshot (see [Using an exit node](#using-an-exit-node-exitnode)) |
| `advertiseConnector` | bool, `false` | `--advertise-connector` — be an app connector |
| `sshAdvertise` | bool, `true` | advertise Tailscale SSH (`--ssh=false` when off) |
| `tags` | list, `[ ]` | `--advertise-tags=…` (must be authorized by the tailnet ACL) |
| `hostname` | str, `null` | `--hostname=…` override the registered name |
| `encryptState` | bool, `false` | TPM-encrypt the `tailscaled` state file |

`encryptState` is **off** by default: our boxes are reflashed often, where a TPM can enter
DA-lockout and crash-loop `tailscaled` (per straylight's note). When off, the module passes
`--encrypt-state=false`. Turn it on only for stable servers with a healthy TPM.

## Routing features auto-detected

```nix
routes = ts.advertiseRoutes != [ ] || ts.advertiseExitNode;
services.tailscale.useRoutingFeatures = if routes then "both" else "client";
```

`useRoutingFeatures` is `"both"` **only when the node actually routes** (it advertises routes or an
exit node); otherwise it's a plain `"client"`. This avoids forcing routing features and
IP-forwarding onto workstations that don't need them. Correspondingly, the IP-forwarding sysctls are
only set when the node routes:

```nix
boot.kernel.sysctl = mkIf routes {
  "net.ipv4.ip_forward" = 1;
  "net.ipv6.conf.all.forwarding" = 1;
};
```

## Using an exit node (`exitNode`)

Exit-node selection is a **runtime, per-device** knob, so it's applied via a `tailscale set`
**oneshot** (`tailscale-exit-node.service`) — *not* `up` flags (which would clobber any manual
`tailscale set` on the next activation). The unit is only emitted when a node is pinned:

```nix
hyper-modern-nixos.network.tailscale.exitNode = "us-mia-wg-001.mullvad.ts.net";
```

→ runs `tailscale set --exit-node=<node> --exit-node-allow-lan-access` (LAN + tailnet stay
reachable; everything else exits through the node). A rebuild re-asserts the pin.

This is how the **Mullvad Miami** routing on `ultraviolence` works (the Mullvad add-on enabled in
the Tailscale console exposes `us-mia-*` exit nodes). To change relays or clear at runtime:

```bash
tailscale exit-node list --filter=USA | grep -i miami
sudo tailscale set --exit-node=us-mia-wg-002.mullvad.ts.net --exit-node-allow-lan-access
sudo tailscale set --exit-node=     # clear (direct egress)
```

To clear a *pinned* node, set `exitNode = null` and run the clear command once (the unit isn't
emitted when null, so it won't auto-clear). See
[SearXNG + torrents](../services/searxng-torrents.md) for the full Miami setup.

## Throughput tuning (`tailscale-ethtool`)

A `oneshot` systemd unit (`tailscale-ethtool`) tunes the default NIC's offloads after
`network-online.target`. UDP GRO forwarding materially improves WireGuard throughput on many drivers
(straylight):

```sh
NETDEV=$(ip -o route get 8.8.8.8 | cut -f5 -d' ')
ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
```

## Firewall posture

The firewall is **on fleet-wide** (`hyper-modern-nixos.network.firewall.enable`, default `true`).
Because `tailscale0` is a `trustedInterface` (all traffic on it allowed), enabling it never blocks
the tailnet or SSH — it only closes the **public** interfaces. Public ports are minimal: TCP `22`
and `3000`, UDP `41641` (the Tailscale endpoint), with `checkReversePath = "loose"`.

The backend is the modern **nftables** backend (`hyper-modern-nixos.network.firewall.nftables`,
default `true` → `networking.nftables.enable`). All rules are expressed through high-level
`networking.firewall.*` options (no raw `iptables`/`extraCommands`), so the backend renders them
natively into a single inspectable `nft list ruleset` (`table inet nixos-fw`).

Per-service, interface-scoped ports merge in cleanly on top — e.g. [postgres](./postgres.md) opens
`5432` only on `tailscale0`, and [attic](./attic.md)/[nativelink](./nativelink.md) open their
gRPC/HTTP ports only on the trusted interfaces. Because the firewall is on everywhere, those
interface-scoped rules actually **enforce** the tailnet-only posture on every host (they're no-ops
when the firewall is off). No host needs to "re-enable" the firewall.

### Exposing a service publicly

To reach a service from outside the tailnet, use **`tailscale serve`** (tailnet HTTPS) or
**`tailscale funnel`** (public HTTPS) terminating at the tailscaled proxy — the service itself stays
bound to loopback/tailnet and you never punch a hole in the firewall. Only add a public
`allowedTCPPorts` entry for the rare service that must face the raw internet directly.
