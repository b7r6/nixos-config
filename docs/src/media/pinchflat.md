# Pinchflat (yt-dlp media manager)

From `modules/nixos/pinchflat.nix` under `hyper-modern-nixos.pinchflat`. **Off
by default.** Live on `guccimane`. Web UI on `:8945`.

[Pinchflat](https://github.com/kieraneglin/pinchflat) is a self-hosted yt-dlp
manager (Elixir/Phoenix): define channels/playlists as **sources** with
download rules and it pulls new content on a schedule; also does one-off URL
downloads. Downloads land in `/var/lib/media`, where the
[library pipeline](./pipeline.md) and the [media servers](./servers.md) pick
them up.

## Packaging: OCI container from our own registry

Pinchflat isn't in nixpkgs. It runs via `virtualisation.oci-containers`
(docker backend), but the image is pulled from the **fleet zot registry**
(`registry.sju1.s4.gl`), not ghcr — so it's R2-backed and reproducible from our
own infra.

### The `-cffi` image (a real fix)

Upstream's image ships a yt-dlp whose Python lacks **`curl_cffi`**, so it has no
browser *impersonation* targets. SoundCloud increasingly requires impersonation;
without it, SoundCloud extraction degrades. Since this library is
SoundCloud-heavy, that's disqualifying.

`packages/pinchflat-image/Dockerfile` is a thin overlay that adds `curl_cffi`
to the image's system Python (the bundled yt-dlp is a *script* under
`/usr/bin/python3`, not a PyInstaller binary, so it picks the module up), with a
build-time assertion that impersonation is actually available. Built and pushed
to zot as `…/pinchflat:<tag>-cffi`; the module's `image` option points at it.

> Pinchflat's source model already allows non-YouTube URLs (the author's own
> "tenuous support" comment in `sources/source.ex`), so with `curl_cffi` present
> SoundCloud sources index and download fine — verified end-to-end via
> `Sources.create_source`. No fork needed.

## Options

| Option | Default | Notes |
|--------|---------|-------|
| `enable` | false | |
| `image` | `registry.sju1.s4.gl/kieraneglin/pinchflat:<tag>-cffi` | the curl_cffi overlay |
| `port` | 8945 | web UI |
| `configDir` | `/var/lib/pinchflat/config` | SQLite DB + state (**authoritative**) |
| `downloadDir` | `/var/lib/media` | shared library root |
| `workerConcurrency` | 2 | `YT_DLP_WORKER_CONCURRENCY` (drop to 1 if IP-limited) |
| `openTailnet` | true | open the port on `tailscale0` only |

`configDir` is declared `authoritative` state (sources/rules/history survive +
back up). Exposure is tailnet-only by default.

## Updating the image

```sh
skopeo copy --policy <insecure> --override-os linux --override-arch amd64 \
  docker://ghcr.io/kieraneglin/pinchflat:<tag> \
  docker://registry.sju1.s4.gl/kieraneglin/pinchflat:<tag>
# then rebuild the -cffi overlay (packages/pinchflat-image), push, bump `image`
```

## Division of labour

Pinchflat is the **acquisition** front-end (subscriptions + queue). It does NOT
do our artist-grouping/tagging — that's the [library pipeline](./pipeline.md),
which sweeps Pinchflat's output in `/var/lib/media`.
