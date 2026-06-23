# Media servers (Navidrome + Jellyfin)

From `modules/nixos/media.nix` under `hyper-modern-nixos.media`. **Off by
default.** Live on `guccimane`.

Two servers, each independently gated, sharing the `/var/lib/media` library:

- **Navidrome** — music. A single Go binary serving a web player + the Subsonic
  API on `:4533`. The natural fit for a tag-driven track/mix collection (every
  mobile Subsonic client talks to it). Reads `libraryRoot/music`.
- **Jellyfin** — video (+ music if you want one app). Web UI on `:8096`, native
  Android/Google-TV client, and **hardware transcoding via NVENC/NVDEC on the
  RTX 5090**. Reads `libraryRoot/video`.

## Options

| Option | Default | Notes |
|--------|---------|-------|
| `enableNavidrome` | false | music server |
| `enableJellyfin` | false | video server |
| `libraryRoot` | `/var/lib/media` | shared root; `music/` + `video/` underneath |
| `navidromePort` | 4533 | |
| `jellyfinPort` | 8096 | |
| `openLan` | true | open ports on the LAN iface (for a Google TV) |
| `lanInterface` | `enp113s0` | which iface to open on |
| `hardwareAcceleration` | `nvidia.enable` | wire Jellyfin for NVENC |

## Library = authoritative state

The module declares `libraryRoot` once as an **`authoritative`**
`hyper-modern-nixos.state.dirs` entry, from which the fleet plumbing derives
both restic backup and impermanence persistence — no edits to `backup.nix` /
`impermanence.nix`. The class carries the semantics
([state model](../architecture/state-and-backup.md)).

## Hardware transcoding

`hardwareAcceleration` defaults on whenever `hyper-modern-nixos.nvidia.enable`
is set (it is on guccimane). The module puts the `jellyfin` user in the
`render` + `video` groups so it can open `/dev/dri/renderD*` and the NVIDIA
devices; the nvidia module already provides the driver + `hardware.graphics`.
The actual codec (NVENC) is then selected in Jellyfin's admin UI →
Playback → Transcoding.

## Reachability

- **Tailnet** — `tailscale0` is trusted fleet-wide, so phone/laptop reach
  `:4533`/`:8096` with no extra firewall rule.
- **LAN** — with `openLan`, the ports (plus Jellyfin's DLNA/discovery UDP
  `1900`/`7359`) open on `lanInterface` so a Google TV / Chromecast that **can't
  join the tailnet** can still reach Jellyfin.

| Service | URL |
|---------|-----|
| Navidrome | `http://guccimane:4533` (LAN) / `http://<tailnet-ip>:4533` |
| Jellyfin | `http://guccimane:8096` / `http://<tailnet-ip>:8096` |

## First-run

Each web UI has a one-time setup wizard (create admin, point libraries at
`/var/lib/media/{music,video}`). The [library pipeline](./pipeline.md) writes
the embedded tags both servers read, so artists/titles/grouping come out right
rather than "Unknown Artist".
