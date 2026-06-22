# Networking design (DNS, TLS, edge)

> Status: **design**, being implemented in sequence. This records the decisions
> and the layering so the build doesn't drift. Grounded in two pieces of prior
> art — `~/src/ps-v4` (topology-registry + CoreDNS generator) and
> `~/src/straylight/straylight-infra` (`fxy.*` tag-roles + a working
> `cloudflared.nix` / `nginx-reverse-proxy.nix`) — taking the best of each and
> avoiding the obvious mistakes in both.

## The problem, in order

1. **DNS is the blocker.** We have no internal naming: services are reached by
   raw `host:port` over the tailnet, and `tailscale serve` (one cert per node,
   HTTPS-only, no wildcards, no arbitrary vhosts) is too limited to be the
   answer. Everything downstream — internal TLS, nginx vhosts, the public edge —
   needs real names that resolve first. **So DNS leads.**
2. **TLS is split-horizon.** We want **internal ACME** *and* **Cloudflare** — not
   either/or. Bulk/internal traffic (media, registry pulls, postgres) must stay
   on the LAN/tailnet with internally-trusted TLS; only deliberately-public doors
   go through Cloudflare. Hairpinning a movie stream up to Cloudflare and back is
   the anti-pattern we are explicitly avoiding.
3. **The edge is `cloudflared`.** Outbound tunnel, no inbound ports, an identity
   bouncer (Cloudflare Access) in front. "Invisible fleet, one guarded door" —
   raises attacker cost without claiming invulnerability. Per-service opt-in.

## The keystone: a typed topology registry (Dhall)

Both prior-art repos converge on "a host registry drives service composition,"
but each makes a mistake we won't repeat:

- **ps-v4** hand-writes zone files via Nix string interpolation — fragile,
  stringly-typed, no validation until CoreDNS rejects it at runtime.
- **straylight-infra** routes everything through Colmena tag→role indirection —
  implicit and hard to trace ("eh", per the operator).

**Decision: the registry is authored in Dhall** (already first-class here — see
`.nix-compile.dhall`, `dhall` in the formatter). Dhall gives a real schema with
types, so the registry is validated *at evaluation* (no dup IPs, every host in a
known zone, names well-formed), and it generates the downstream artifacts (Nix
host attrs, CoreDNS zones, nginx vhosts, cloudflared ingress) from one source
instead of three hand-maintained lists (today's `keys.nix` + `lib/monitors.nix`
+ `configurations/default.nix`).

Each host carries the **three-name identity** from ps-v4 (its one genuinely great
idea), plus role/zone and the address split:

| Field | Example | Purpose |
| --- | --- | --- |
| `physical` | `watchtower` | the NixOS attr name |
| `tailnet` | `watchtower` | MagicDNS short label (suffix added centrally) |
| `logical` | `watchtower.sju1.s4.gl` | the stable internal name nginx/DNS use (`<host>.<dc>.s4.gl`) |
| `dc` | `sju1` | nearest Equinix DC code (geo key; how the fleet grows distributed) |
| `tailnet_ipv4` | `100.x.y.z` | internal address (served by CoreDNS today) |
| `provider_ipv4` | `null` now; real on Latitude later | public/provider address (forward-compat for bare metal) |
| `role` | `server` / `workstation` / `laptop` / `accelerator` | coarse machine kind |
| `services` | `[ "postgres" "attic" "registry" ]` | service tags; drives DNS CNAMEs + composition |
| `managed` | `true` | is this a deployable nixosConfiguration? (gossamer = false) |

The `tailnet_ipv4` vs `provider_ipv4` split matters little on today's tailnet-only
fleet but is exactly what a Latitude/bare-metal move needs — so it's built in now.

### Implemented (registry layer)

The registry lives in `registry/`:

- **`registry/schema.dhall`** — the typed schema (`Host`, `Zone`, `Registry`).
- **`registry/hosts.dhall`** — the data: all 7 hosts (6 managed + gossamer), with
  real `tailnet_ipv4` and `logical` names `<physical>.<dc>.s4.gl` (e.g.
  `watchtower.sju1.s4.gl`). **`s4.gl`** is our real domain (Njalla), so internal
  names can get real DNS-01 ACME certs; **`<dc>`** is the nearest Equinix DC code
  (`sju1` = San Juan), the geo key the fleet grows distributed along.
- **`registry/registry.json`** — the **committed** Dhall→JSON render that Nix reads.

Dhall is the source of truth (typechecked + total). Nix reads the committed JSON
rather than rendering at eval time — import-from-derivation breaks under
`nix flake check`, and a committed artifact is the standard IFD-free pattern (like
a lockfile). Two dev commands keep it honest:

```sh
nix run .#topology-render   # Dhall → registry/registry.json (after editing *.dhall)
nix run .#topology-check    # CI guard: committed JSON in sync with the Dhall?
```

`modules/nixos/topology.nix` exposes it as `hyper-modern-nixos.topology` (always
on, pure data) with read-only `registry` / `hosts` / `managedHosts` and query
`helpers` (`hostsWithService`, `hostsByRole`, `self`, `tailnetFqdn`). Semantic
validation (duplicate IPs, hosts in undeclared zones) runs as build assertions on
top of Dhall's type checking. CoreDNS/nginx/cloudflared (next) read from here.

## Layer 1 — CoreDNS (implemented)

`modules/nixos/coredns.nix` (`hyper-modern-nixos.coredns`, off by default), built
on stock `services.coredns`. Authoritative for the internal zone `sju1.s4.gl`,
**generated from the topology registry** (never hand-written Nix zone strings —
the ps-v4 mistake we avoided), forwarding everything else out (MagicDNS
`100.100.100.100` first so `*.ts.net` still resolves). Three record kinds, all
derived from the registry:

| Record | Source | Example |
| --- | --- | --- |
| `<host>.sju1.s4.gl` A | `tailnet_ipv4` (every host) | `ultraviolence.sju1.s4.gl → 100.71.82.73` |
| `<host>.lan.sju1.s4.gl` A | `lan_ipv4` (static-leased boxes only) | (pending wired leases) |
| `<service>.sju1.s4.gl` CNAME | host running that `services` tag | `registry.sju1.s4.gl → watchtower…` |

The NS glue is auto-derived from the resolver's own registry entry. It binds
`0.0.0.0` so **both** LAN devices (the Google TV, via the `lan.` records) and
tailnet boxes resolve it. Split-horizon is what makes "a movie stays on the LAN"
true: an internal name resolves to a `tailnet_ipv4`/`lan_ipv4`, never to a
Cloudflare edge.

> **Proven live on watchtower** (the fleet resolver): `ultraviolence.sju1.s4.gl`
> → tailnet IP; `registry.sju1.s4.gl` → `watchtower` (CNAME chain);
> `one.one.one.one` forwards out; `*.osiris-walleye.ts.net` still resolves via
> MagicDNS. `:53` was free (resolved inactive).

> Not yet enabled fleet-wide — watchtower is the single resolver for now. LAN
> clients (the Google TV) point DNS at it (router DHCP option 6) once the `lan.`
> records are populated. Per-host CoreDNS / a second resolver for redundancy is a
> later step.

## Layer 2 — nginx reverse proxy (on every box that serves)

Adapt straylight-infra's `nginx-reverse-proxy.nix` (vhosts, upstreams, websocket,
headers — trimmed of the trading-grade load-balancing/health-check machinery we
don't need yet). Services bind **loopback**; nginx is the vhost router on the
`logical` names. Two TLS sources, by horizon:

- **Internal ACME** — `security.acme` + `virtualHosts.<n>.enableACME` with
  **DNS-01** against a real domain we control (HTTP-01 can't validate internal
  names). Real, browser-trusted certs for internal `logical` names, with **no CA
  to distribute** to every box. (An internal CA + wildcard is the fallback if we
  ever want fully-offline issuance.)
- **Public** — see Layer 3; nginx still terminates/serves, cloudflared dials in.

## Layer 3 — cloudflared (the public edge, opt-in)

Near-copy of straylight-infra's `cloudflared.nix`: tunnel token via agenix,
declarative `ingress` (hostname/path → local service), `dev`/`prod` env selecting
the secret, catch-all 404. **Off by default; every public hostname is an explicit
ingress entry** — the discipline is keeping that list short. Cloudflare terminates
TLS at its edge and the tunnel dials out to nginx/loopback; no inbound ports on
our origin.

**Trust note (named, not hand-waved):** a tunnel is TLS-to-edge, *not* E2E —
Cloudflare sees plaintext of whatever flows through it. Fine for the public doors;
it is the reason internal/bulk traffic does **not** use this path.

## How the horizons compose

```
              ┌─────────────── public internet ───────────────┐
              │                                                │
        Cloudflare edge (TLS term + Access bouncer)            │
              │  cloudflared (outbound tunnel, opt-in ingress) │
   ───────────┼────────────────────────────────────────────────
   origin box │  nginx (vhosts on logical names)               │
              │   ├── internal ACME TLS (DNS-01)  ◄── LAN/tailnet clients
              │   └── loopback upstream ─► service (zot/forgejo/searxng/…)
              │  CoreDNS (logical → tailnet_ipv4, split-horizon)
              └── tailscale (the encrypted fabric underneath)
```

Internal clients resolve a `logical` name via CoreDNS → an internal IP → nginx on
that box → loopback service, with internal-ACME TLS. The movie never leaves the
LAN. A *public* name resolves (at Cloudflare) to the tunnel → nginx → service.
Same nginx, same service binding; only the path in differs.

## What we deliberately drop from the prior art

- **Colmena tag→role deployment** (straylight-infra) — we already have
  `nix run .#deploy-fleet`; the tag indirection is implicit and not worth it.
- **Geo-zones / ZK ensembles / venue keys** (ps-v4) — trading-fleet specifics
  irrelevant to a homelab; the registry keeps `zone`/`region` *fields* for
  forward-compat but no ensemble machinery.
- **Hand-written Nix zone strings** (ps-v4) — replaced by Dhall-generated zones.

## Build order

1. **Dhall topology registry** + the Nix bridge that exposes it (validated;
   consolidates `keys.nix`/`monitors.nix`/host lists).
2. **CoreDNS** module, zones from the registry, split-horizon, on every box.
3. **nginx reverse proxy** module + internal ACME (DNS-01) for `logical` names.
4. **cloudflared** module (off by default), first public door as a proof.

Each lands and is proven before the next. DNS first, because everything else
needs names that resolve.

## Decided

- **Naming scheme + domain: `<host>.<dc>.s4.gl`** — `s4.gl` is our real Njalla
  domain; `<dc>` is the nearest Equinix DC code (`sju1` = San Juan, single-site
  today). Internal names are real, public-zone names → real DNS-01 ACME certs.
- **Internal TLS via DNS-01** on `s4.gl` (not an internal CA): no CA to distribute,
  real trust chain. Split-horizon CoreDNS resolves `*.s4.gl` internal names to
  `tailnet_ipv4`; the public `s4.gl` zone (Njalla / future Cloudflare) is separate.

## Open decisions

- Which **DNS-01 provider/credential** lego uses against `s4.gl` — Njalla has an
  API; alternatively delegate the zone (or an `_acme-challenge` subdomain) to
  Cloudflare for lego's well-supported CF provider. (Decide at the nginx/ACME step.)
- The Tailscale **tailnet rename** (separate Tailscale-console task; `tailnetSuffix`
  in the registry updates in one place when done).
