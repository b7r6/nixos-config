# media pipeline

Filename-driven metadata extraction + tagging for a messy download library (SoundCloud/YouTube rips
with empty embedded tags). Turns `Hex Cougar - Sex U [293196542].m4a` into clean, grouped,
properly-tagged audio that Navidrome/Jellyfin (see `modules/nixos/media.nix`) browse correctly.

This is **library tooling**, run by hand against `/var/lib/media` (or a staging dir). Only the
scripts are tracked; all manifests/caches/materialized trees are generated and `.gitignore`d
(they're large and specific to one collection).

> Provenance: this pipeline is also how we found the atticd NAR-prefetch bug — a cold multi-GB cache
> pull during a re-tag run surfaced the serialized chunk fetch. Worth keeping sharp.

## The stages

| script | role | |--------|------| | `organize_media.py` | parse filenames → structured records
(artist, title, feat, remixer, mix-type, source id); unicode/promo normalization; primary-artist
grouping. Emits a manifest. | | `enrich.py` | for title-only files, re-query the source by `[id]`
via `yt-dlp` and recover artist/title (uploader-as-artist or parse the source title). Self-healing
retry sweeps for R2/SoundCloud rate limits. | | `tag.py` | write `artist`/`albumartist`/`title` (+
`feat.`) into the files via mutagen (MP4 + ID3). `albumartist` = primary artist, so collabs group.
Dry-run by default. | | `walk.py` | graph-walk discovery: from seed artist profiles, list their
sets; expand the frontier to collaborators. | | `seams.py` | edge-case detector / fixpoint oracle:
flags empty-artist, residual unicode/promo, missing/suspect primary, casing collisions. Exit nonzero
if any seam. | | `discover.py` | enumerate a profile's playlists/sets (no download). | | `check.py`
| ad-hoc manifest spot-check helper. |

## Typical run

Needs `yt-dlp` + `python3Packages.mutagen` (use `nix-shell -p`):

```sh
cd /path/to/library              # the scripts write manifests next to themselves
python3 organize_media.py --src . --dest organized --manifest manifest.json          # dry run
python3 organize_media.py --src . --dest organized --manifest manifest.json --apply

# recover artists for title-only files (re-query source by id)
nix-shell -p yt-dlp --run 'python3 enrich.py --manifest manifest.json --out enriched_manifest.json --cache enrich_cache.json'

# verify we're at a fixpoint (no parser edge cases)
python3 seams.py enriched_manifest.json     # exit 0 == clean

# write tags (dry run, then apply)
nix-shell -p python3Packages.mutagen --run 'python3 tag.py --manifest enriched_manifest.json --media-root /var/lib/media/music'
nix-shell -p python3Packages.mutagen --run 'python3 tag.py --manifest enriched_manifest.json --media-root /var/lib/media/music --apply'
```

Pipeline is idempotent: re-running skips already-done work; `tag.py` re-tags in place. After
tagging, restart navidrome to rescan.

## Discovery / batch ingest

```sh
nix-shell -p yt-dlp --run 'python3 walk.py discover https://soundcloud.com/<artist> ...'
# then yt-dlp --download-archive ... the candidates, re-run organize→enrich→tag
```
