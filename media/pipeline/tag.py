#!/usr/bin/env python3
"""
tag.py — write embedded artist/title/albumartist tags into the deployed media
files from the (enriched) manifest, so BOTH Navidrome and Jellyfin show rich
metadata instead of "[Unknown Artist]".

Why embedded tags (not a player import): Navidrome and Jellyfin each read tags
straight from the file. Writing real tags fixes both at once, survives rescans
and reinstalls, and couples to nothing.

Matching: files in --media-root are indexed by the [id] in their name, then
matched to manifest records by source_id (the manifest's dest paths were not
recomputed after enrichment, so id is the stable join key).

Tags written:
  - title        ← record.title
  - artist       ← record.artist (+ "feat. X" appended if featured present)
  - albumartist  ← record.artist (so Navidrome groups by the primary artist)
  - album        ← only if we can infer one; otherwise left untouched
  - comment      ← "source:<sc|yt>:<id>" for traceability

Formats: MP4/M4A (mutagen.mp4) and MP3/ID3 (mutagen.easyid3). Other extensions
are skipped. Default is a DRY RUN; pass --apply to write.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from mutagen.easyid3 import EasyID3
from mutagen.id3 import ID3NoHeaderError
from mutagen.mp4 import MP4


ID_RE = re.compile(r"\[([^\[\]]+)\]\.[^.]+$")

# MP4 atom names for the fields we set
MP4_KEYS = {
  "title": "\xa9nam",
  "artist": "\xa9ART",
  "albumartist": "aART",
  "album": "\xa9alb",
  "comment": "\xa9cmt",
}


def file_id(p: Path) -> str | None:
  m = ID_RE.search(p.name)
  return m.group(1) if m else None


def artist_display(rec: dict) -> str:
  a = rec.get("artist", "").strip()
  feat = rec.get("featured", [])
  if a and feat:
    return f"{a} feat. {', '.join(feat)}"
  return a


def planned_tags(rec: dict) -> dict[str, str]:
  artist = rec.get("artist", "").strip()
  # albumartist = the PRIMARY artist (groups collabs under one artist in
  # Navidrome); fall back to the full credit if primary wasn't computed.
  primary = (rec.get("artist_primary") or artist).strip()
  tags: dict[str, str] = {}
  if rec.get("title"):
    tags["title"] = rec["title"].strip()
  if artist:
    tags["artist"] = artist_display(rec)
    tags["albumartist"] = primary
  src = rec.get("source")
  sid = rec.get("source_id")
  if src and sid:
    code = {"soundcloud": "sc", "youtube": "yt"}.get(src, src)
    tags["comment"] = f"source:{code}:{sid}"
  return tags


def write_mp4(path: Path, tags: dict[str, str]) -> None:
  mp4 = MP4(str(path))
  for k, v in tags.items():
    atom = MP4_KEYS.get(k)
    if atom:
      mp4[atom] = [v]
  mp4.save()


def write_mp3(path: Path, tags: dict[str, str]) -> None:
  try:
    ez = EasyID3(str(path))
  except ID3NoHeaderError:
    ez = EasyID3()
    ez.filename = str(path)
  for k, v in tags.items():
    # EasyID3 uses these exact keys
    key = {"comment": "website"}.get(k, k)  # comment isn't an EasyID3 key; stash in website
    if key == "website":
      continue  # skip the traceability comment for mp3 (optional)
    ez[key] = v
  ez.save()


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--manifest", default=".organize/enriched_manifest.json")
  ap.add_argument("--media-root", default="/var/lib/media/music")
  ap.add_argument("--apply", action="store_true", help="actually write tags")
  ap.add_argument("--show", type=int, default=15, help="how many planned rows to print")
  args = ap.parse_args()

  recs = json.load(open(args.manifest, encoding="utf-8"))
  by_id = {r["source_id"]: r for r in recs if r.get("source_id")}

  root = Path(args.media_root)
  files = [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in (".m4a", ".mp3")]

  matched = unmatched = no_artist = 0
  planned: list[tuple[Path, dict]] = []
  for p in files:
    fid = file_id(p)
    rec = by_id.get(fid) if fid else None
    if not rec:
      unmatched += 1
      continue
    matched += 1
    tags = planned_tags(rec)
    if "artist" not in tags:
      no_artist += 1
    planned.append((p, tags))

  print(f"media files       : {len(files)}")
  print(f"matched to manifest: {matched}")
  print(f"unmatched (skip)  : {unmatched}")
  print(f"matched w/o artist: {no_artist}")
  print()
  print(f"--- planned tags (first {args.show}) ---")
  for p, tags in planned[: args.show]:
    rel = p.relative_to(root)
    print(f"  {rel}")
    print(
      f"    artist={tags.get('artist', '')!r} albumartist={tags.get('albumartist', '')!r} title={tags.get('title', '')!r}"
    )

  if not args.apply:
    print("\n[dry run] no tags written. re-run with --apply to write.")
    return 0

  ok = err = 0
  errors: list[str] = []
  for p, tags in planned:
    if not tags:
      continue
    try:
      if p.suffix.lower() == ".m4a":
        write_mp4(p, tags)
      else:
        write_mp3(p, tags)
      ok += 1
    except Exception as e:
      err += 1
      errors.append(f"{p.name}: {e}")
  print(f"\ntagged ok : {ok}")
  print(f"errors    : {err}")
  for e in errors[:10]:
    print(f"  ! {e}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
