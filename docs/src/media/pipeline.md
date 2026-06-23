# Library pipeline (sort / enrich / tag)

Source in `media/pipeline/`. **Run-by-hand tooling**, not part of the NixOS
build. Turns a flat pile of SoundCloud/YouTube rips with **empty embedded tags**
into clean, grouped, properly-tagged audio that [Navidrome/Jellyfin](./servers.md)
browse correctly.

> This is also the tooling that surfaced the
> [atticd NAR-prefetch bug](../architecture/attic-prefetch.md) — a cold cache
> pull during a re-tag run exposed it. It earns a tracked home.

## The core problem

The files look like `Hex Cougar - Sex U [293196542].m4a`. Embedded tags are
**empty** (yt-dlp/SoundCloud rips), so the **filename is the only metadata** —
and the trailing `[id]` is a SoundCloud track id (numeric) or YouTube id
(11-char). The pipeline extracts structure from the name, recovers what's
missing from the source, and writes real tags.

## Stages

| script | role |
|--------|------|
| `organize_media.py` | parse filename → record (artist, title, featured, remixer, mix-type, source id). Unicode/promo normalization; **primary-artist grouping**. Emits a manifest. |
| `enrich.py` | for title-only files, re-query the source by `[id]` via `yt-dlp` and recover artist/title. Cached + **self-healing retry sweeps** for rate limits. |
| `tag.py` | write `artist` / `albumartist` / `title` (+ `feat.`) via **mutagen** (MP4 + ID3). `albumartist` = primary artist so collabs group. Dry-run by default. |
| `walk.py` | graph-walk discovery: from seed artist profiles, list their sets; expand the frontier to collaborators. |
| `seams.py` | **edge-case detector / fixpoint oracle** — flags empty-artist, residual unicode/promo, missing/suspect primary, casing collisions. Exit nonzero if any seam remains. |
| `discover.py` | enumerate a profile's playlists/sets (no download). |

## Hard-won parsing rules (the "seams")

Each of these was a real bug found by running over the live library:

- **Unicode dividers** — rips substitute fs-unsafe chars: `⧸`→`/`, fullwidth
  `，`→`,`, `：`→`:`, fullwidth letterforms folded via NFKC, zero-width/BOM
  stripped.
- **Primary-artist grouping** — `Hex Cougar & ryscu`, `Kindrid, Syberlilly`
  split on join chars (`&`/`,`/`x`/`pres.`) to a **primary** written to
  `albumartist`, so collabs group under one artist instead of fragmenting.
  …with an **allowlist** for acts whose *name* contains a joiner
  (`Above & Beyond`).
- **Casing canonicalization** — `wevlth`/`WEVLTH`, `deadmau5`/`Deadmau5` merge
  to the most-frequent spelling (else they're separate artists).
- **Promo cruft** — `*FREE DL*`, `| FREE DOWNLOAD`, `🌀FREE DL🌀`,
  `*VIDEO IN DESCRIPTION*` stripped from titles.
- **Artist recovery** — title-only files have no artist in the name; re-query
  the source: if its title is `Artist - Title`, parse it; else the **uploader is
  the artist** (the artist uploaded their own track).

## Typical run

Needs `yt-dlp` + `python3Packages.mutagen` (via `nix-shell -p`). Manifests/caches
are written next to the library and are **gitignored** (large, library-specific):

```sh
cd /var/lib/media         # or a staging dir
python3 organize_media.py --src . --dest organized --manifest manifest.json          # dry run
python3 organize_media.py --src . --dest organized --manifest manifest.json --apply

nix-shell -p yt-dlp --run 'python3 enrich.py --manifest manifest.json \
  --out enriched_manifest.json --cache enrich_cache.json'

python3 seams.py enriched_manifest.json      # exit 0 == fixpoint, no edge cases

nix-shell -p python3Packages.mutagen --run 'python3 tag.py \
  --manifest enriched_manifest.json --media-root /var/lib/media/music --apply'
# then: systemctl restart navidrome   (rescan)
```

Idempotent: re-runs skip done work; `tag.py` re-tags in place. The full
`media/pipeline/README.md` has the discovery/batch-ingest flow.

## Lint scoping

These are pragmatic run-by-hand scripts. `ruff.toml` has a `per-file-ignores`
entry for `media/pipeline/**` that keeps correctness checks (pyflakes `F`,
naming `N`) but relaxes stylistic rules (`PTH`/`SIM`/`PERF`/ambiguous-unicode —
ironic given the domain). Don't churn working, tested scripts for style.
