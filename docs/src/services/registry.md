# OCI registry (zot → R2)

A container/OCI image registry, from `modules/nixos/registry.nix` under
`hyper-modern-nixos.registry`. **Off by default.** Live on `watchtower`.

[zot](https://zotregistry.dev) is a production-ready, vendor-neutral OCI
registry. It runs as a **plain systemd service — not the Docker daemon** — and
stores blobs directly in **Cloudflare R2** via its core S3 driver.

## Why zot (and how it's built)

zot isn't in nixpkgs, so it's packaged in-repo (`packages/zot`, exposed as
`pkgs.zot`). We build the **minimal** flavour: S3/remote storage is *core* in zot
(not an extension), so an R2-backed registry needs none of the heavy extensions —
which also avoids the `zui` npm build and the search/trivy dependency surface. The
binary logs `binary-type: minimal` and skips ui/search/mgmt/trust routes by
design.

## Storage & state tiering

Blobs and manifests live in the dedicated **`straylight-oci`** R2 bucket. The
local `/var/lib/zot` dir is only a working cache, so it's classified
**`reconstructible`** ([state model](../architecture/state-and-backup.md)):
persisted across an impermanence reboot (warm), **never backed up** — R2 holds the
authoritative content. There is no database and no PITR: with remote storage we
run `dedupe = false` (the dedupe index would otherwise need a remote DB), `gc` on.

## Exposure

On `watchtower` zot binds **`127.0.0.1`** and is fronted by **nginx/TLS** at
`registry.sju1.s4.gl` (see [below](#nginx-front--tls)). The module *default* is
`listenAddress = "0.0.0.0"` (binding the `tailscale0` IP directly races boot),
with the firewall — **on fleet-wide** — opening the port (`5000`) **only on
`tailscale0`**; that's the tailnet-only posture for a node *without* the reverse
proxy. watchtower overrides `listenAddress` to loopback because zot now sits
behind nginx rather than facing the tailnet directly.

## Credentials

The R2 access key / secret are the AWS SDK vars `AWS_ACCESS_KEY_ID` /
`AWS_SECRET_ACCESS_KEY`, from the self-wired [`zot-r2-env`](../infrastructure/secrets.md)
agenix secret, fed to the unit via systemd `EnvironmentFile` — never the Nix
store (same pattern as the other R2 consumers).

```nix
# configurations/nixos/watchtower/configuration.nix
hyper-modern-nixos.registry = {
  enable = true;
  listenAddress = "127.0.0.1";               # behind nginx — bind loopback
};

# nginx fronts it at registry.sju1.s4.gl with the wildcard cert
hyper-modern-nixos.reverseProxy = {
  enable = true;
  services.registry.port = 5000;
};
```

## Options

| Option | Type / default | Description |
| --- | --- | --- |
| `registry.enable` | `bool` / `false` | Run the zot registry. |
| `registry.port` | `port` / `5000` | HTTP port (opened on `tailscale0` only). |
| `registry.listenAddress` | `str` / `"0.0.0.0"` | Bind address (firewall gates to tailnet). |
| `registry.openTailnet` | `bool` / `true` | Open `port` on `tailscale0`. |
| `registry.dataDir` | `str` / `"/var/lib/zot"` | Local cache dir (`reconstructible`). |
| `registry.secret` | `null or str` / `"zot-r2-env"` | agenix secret with the `AWS_*` R2 creds. |
| `registry.s3.bucket` | `str` / `"straylight-oci"` | R2 blob bucket. |
| `registry.s3.endpoint` | `str` / R2 endpoint | R2 S3 endpoint (account-scoped). |
| `registry.s3.region` | `str` / `"auto"` | S3 region (R2 = auto). |

## Using it

The registry speaks the OCI distribution API on the tailnet. Push/pull with any
OCI client (skopeo, podman, docker, oras, nix's own copy):

```sh
# inspect health / catalog
curl http://watchtower:5000/v2/
curl http://watchtower:5000/v2/_catalog

# push an image (skopeo, over the tailnet)
skopeo copy --dest-tls-verify=false \
  docker://busybox:latest \
  docker://watchtower:5000/test/busybox:latest

# pull / inspect it back
skopeo inspect --tls-verify=false docker://watchtower:5000/test/busybox:latest
```

> **Proven live on watchtower** (2026-06): pushed busybox via skopeo →
> `_catalog` shows `test/busybox`; the blobs (5 objects, 2.1 MiB) landed in the
> `straylight-oci` R2 bucket (verified independently via rclone); pull round-trip
> returned the full manifest.

> TLS: zot itself serves plain HTTP on loopback (`127.0.0.1:5000`); the
> public-facing TLS is terminated by **nginx** at `registry.sju1.s4.gl` (see
> below). The `--dest-tls-verify=false` flag is only for pushing *directly* to
> the loopback port (e.g. on-box). zot *can* terminate TLS natively
> (`http.tls.{cert,key}`), but we let nginx be the single TLS edge instead.

## nginx front + TLS

> Status: **live on watchtower.** zot binds `127.0.0.1:5000` and nginx fronts it
> at `registry.sju1.s4.gl` with a real wildcard cert.

watchtower runs the **nginx reverse proxy** (`hyper-modern-nixos.reverseProxy`),
routing on CoreDNS names, which escapes `tailscale serve`'s limits (one cert per
node, HTTPS-only, no wildcards, no arbitrary vhosts). Every HTTP service —
zot/searxng/forgejo/… — converges on the same shape: **bind `127.0.0.1`, let
nginx be the vhost router.** For zot that's `listenAddress = "127.0.0.1"` plus
`reverseProxy.services.registry.port = 5000`. nginx terminates TLS on
`registry.sju1.s4.gl` with a **real wildcard cert** (`*.sju1.s4.gl`, issued via
DNS-01 against the public `s4.gl` domain through Njalla) and proxies to the
loopback upstream. CoreDNS already resolves `registry.sju1.s4.gl` to this host's
tailnet/LAN IP, so clients hit nginx over the tailnet/LAN and never touch the
zot port directly.

This homelab layer is a **dress rehearsal for the production edge**, which will be
one of two shapes — both of which sit on top of the *same* internal substrate
(services on loopback + nginx + CoreDNS), so this substrate is rework-free
either way:

- **Public ACME TLS** — nginx terminates HTTPS with real certs. On NixOS the
  idiomatic path is `security.acme` + `virtualHosts.<n>.enableACME`; for
  internal CoreDNS names this needs **DNS-01 against a real public domain** (HTTP-01
  can't validate non-public names). nginx also gained native in-process ACME
  (`ngx_http_acme_module`, ~2025), but NixOS's `security.acme`/lego is the
  established route.
- **Cloudflare Tunnel** (`cloudflared`, outbound) — no inbound ports, no cert
  management on our side; Cloudflare terminates at the edge and the tunnel dials
  out to nginx/services. Far simpler than the old `argo-tunnel` era.

Internal HTTPS is already settled (and live): **DNS-01 real wildcard certs**,
the first option above. The only open decision is the **production edge/cert
strategy** (public ACME vs Cloudflare Tunnel) — and the internal nginx+CoreDNS
substrate, which is live now, is common to both.
