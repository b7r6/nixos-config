# Media stack — overview

A self-hosted media stack on **guccimane** (the workstation: Ryzen 9 9950X3D +
RTX 5090), plus the tooling that keeps the library clean. All gated, all
tailnet-first.

## The pieces

| Piece | What | Module / location |
|-------|------|-------------------|
| **Navidrome** | music server (web + Subsonic API), `:4533` | `modules/nixos/media.nix` |
| **Jellyfin** | video server (web + Google-TV client, NVENC on the 5090), `:8096` | `modules/nixos/media.nix` |
| **Pinchflat** | yt-dlp media manager (subscribe/queue YouTube **and** SoundCloud) | `modules/nixos/pinchflat.nix` |
| **Dropbox** | "secret-gist" shareable URLs for arbitrary files | `modules/nixos/dropbox.nix` + `packages/drop` |
| **Library pipeline** | filename→metadata extraction + tagging (run by hand) | `media/pipeline/` |
| **queuedrop** | PureScript browser extension: queue a URL to the server | `tools/queuedrop/` |

## How they fit together

```text
                       browser (queuedrop ext / bookmarklet)
                                  │  POST {url}
                                  ▼
                         queue endpoint  ──►  Pinchflat (yt-dlp)
                                                   │ downloads
                                                   ▼
   library pipeline  ◄────────────────────  /var/lib/media/{music,video}
   (organize→enrich→tag: clean names,              │ reads tags
    grouped artists, embedded metadata)            ▼
                                          Navidrome / Jellyfin
```

- **`/var/lib/media`** is the shared library root — declared **`authoritative`**
  state (restic-backed + impermanence-persisted via the
  [state model](../architecture/state-and-backup.md)). `music/` → Navidrome,
  `video/` → Jellyfin; Pinchflat downloads land here too.
- The **library pipeline** is the metadata brain: the source files are
  SoundCloud/YouTube rips with **empty embedded tags**, so it parses the
  filename, recovers artists by re-querying the source by id, and writes real
  tags so both servers browse correctly. See [pipeline](./pipeline.md).

## Reachability

The fleet firewall trusts `tailscale0`, so phones/laptops reach everything over
the tailnet with no extra rules. The media ports are **also** opened on the LAN
interface so a **Google TV / Chromecast** (which can't join the tailnet) can
reach Jellyfin. See each page for specifics.

## Why a workstation, not watchtower

guccimane has the GPU (RTX 5090 → Jellyfin NVENC transcoding) and the big local
disk for the library. watchtower stays the lean always-on infra node
(postgres/attic/registry/supabase).
