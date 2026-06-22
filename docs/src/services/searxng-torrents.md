# SearXNG + torrents

Two tailnet-facing services incubating on `ultraviolence`, plus the Mullvad Miami exit-node routing
that sits underneath them. Both are off-by-default `hyper-modern-nixos.*` modules, so they can
graduate to a dedicated host by flipping `enable` elsewhere.

| service | module | port (on ultraviolence) | reach | |---|---|---|---| | SearXNG |
`modules/nixos/searxng.nix` | `8889` (`8888` taken by docker there) | tailnet | | flood (web UI) |
`modules/nixos/torrents.nix` | `3001` | tailnet | | transmission (RPC) |
`modules/nixos/torrents.nix` | `9091` | loopback | | transmission (peer) |
`modules/nixos/torrents.nix` | `51413` | all ifaces |

All egress from the box — including transmission — exits **Mullvad Miami** (see
[Exit node](#mullvad-miami-exit-node) below and [Tailscale](../infrastructure/tailscale.md)).

## SearXNG

`hyper-modern-nixos.searxng` — a privacy-maxed metasearch:

- no metrics / `disable-logging`, image proxy on, `google`/`bing` engines off, a curated engine set
  (ddg, brave, startpage, wikipedia, github, hackernews, arch/nixos wikis).
- **`json` / `csv` / `rss` formats enabled and the bot-detection `limiter` OFF** — so the API is
  freely scriptable on the tailnet (e.g. as an LLM web-search backend). Turn `limiter = true` only
  if ever exposed publicly.
- `secret_key` comes from the agenix env file `searxng-env`
  (`SEARXNG_SECRET=$(openssl rand -hex 32)`), via `$SEARXNG_SECRET` envsubst.
- valkey (`redisCreateLocally`) backs the rate-limit/cache store; runs under uwsgi (`http` socket).

```nix
hyper-modern-nixos.searxng = {
  enable = true;
  listenAddress = "0.0.0.0"; # tailnet-reachable (firewall gates to tailscale0)
  port = 8889;               # 8888 collides with a docker container here
};
age.secrets.searxng-env.file = ../../../secrets/agenix/machines/searxng-env.age;
```

Use the JSON API:

```bash
curl -s 'http://ultraviolence.osiris-walleye.ts.net:8889/search?q=nixos&format=json' | jq .
```

Options: `port`, `listenAddress`, `baseUrl`, `environmentFile`, `openTailnet`, `limiter`.
Authoritative source: `modules/nixos/searxng.nix`.

## Transmission + flood

`hyper-modern-nixos.torrents` — `transmission_4` daemon + `flood` web UI:

- transmission RPC binds **loopback only** (`127.0.0.1:9091`); flood is the client. Peer port
  `51413` is opened for connectivity; `encryption = required`, dht/pex/utp on.
- RPC password from the agenix `credentialsFile` (`transmission-rpc`, JSON `{"rpc-password":"…"}`) —
  transmission salts it on first start.
- `download-dir` + `incomplete-dir` are pre-created via `systemd.tmpfiles` (transmission's sandbox
  needs `incomplete-dir` to exist before start).
- flood is served on the tailnet (`floodPort = 3001`).
- **No per-app killswitch**: transmission follows the host default route, so it exits wherever the
  box exits (Miami, via the exit node).

```nix
hyper-modern-nixos.torrents.enable = true;
age.secrets.transmission-rpc.file = ../../../secrets/agenix/machines/transmission-rpc.age;
```

First use of flood:

1. Open `http://ultraviolence.osiris-walleye.ts.net:3001`.
2. Choose **Transmission**, host `127.0.0.1`, port `9091`, user `transmission`.
3. Password: `sudo cat /run/agenix/transmission-rpc` on the box (the `rpc-password` value).

Options: `downloadDir`, `peerPort`, `rpcPort`, `floodPort`, `credentialsFile`, `openTailnet`.
Authoritative source: `modules/nixos/torrents.nix`.

## Mullvad Miami exit node

The "exit via Miami" uses **Tailscale's built-in Mullvad exit nodes** (the Mullvad add-on, enabled
in the Tailscale admin console — not the local `mullvad` daemon). Exit-node selection is a runtime,
per-device knob, so the [Tailscale module](../infrastructure/tailscale.md) applies it via a
`tailscale set` **oneshot** (`tailscale-exit-node.service`), not `up` flags.

Pinned declaratively on ultraviolence:

```nix
hyper-modern-nixos.network.tailscale.exitNode = "us-mia-wg-001.mullvad.ts.net";
```

This runs `tailscale set --exit-node=us-mia-wg-001.mullvad.ts.net --exit-node-allow-lan-access` so
the LAN/tailnet stays reachable while all other egress exits Miami.

There are ~6 `us-mia-*` relays. To switch at runtime (e.g. if Mullvad retires `-001`):

```bash
tailscale exit-node list --filter=USA | grep -i miami   # see the options
sudo tailscale set --exit-node=us-mia-wg-002.mullvad.ts.net --exit-node-allow-lan-access
sudo tailscale set --exit-node=                          # clear (back to direct)
```

Verify the egress location:

```bash
curl -s https://am.i.mullvad.net/json | jq '{city, country, server: .mullvad_exit_ip_hostname}'
# -> { "city": "Miami, FL", "country": "USA", "server": "us-mia-wg-001" }
```

> Note: the host firewall is **on fleet-wide** (the module default), so the `tailscale0`-scoped
> firewall rules in these modules **do** gate the ports — SearXNG and flood are reachable only on
> the tailnet, even though they bind broadly (binding the `tailscale0` IP directly races boot, so
> `0.0.0.0` + a `tailscale0`-only firewall rule is the pattern). To reach either off-tailnet, front
> it with `tailscale serve` / `tailscale funnel` rather than opening a public firewall port.
