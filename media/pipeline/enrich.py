#!/usr/bin/env python3
"""
enrich.py — recover real artist/title for title-only files by re-querying the
source (SoundCloud / YouTube) using the [id] we preserved in every filename.

Strategy (proven against live data):
  - SoundCloud numeric id  -> https://api.soundcloud.com/tracks/<id>
  - YouTube 11-char id     -> https://www.youtube.com/watch?v=<id>
  fetched via `yt-dlp --dump-single-json --skip-download`.

Merge rule for the recovered metadata:
  - if the SOURCE TITLE contains " - "  -> it's "Artist - Title" (label upload);
    parse it with the same grammar as the filename parser.
  - else                                -> the UPLOADER is the artist (the artist
    uploaded their own track), source title is the title.

Everything fetched is cached to enrich_cache.json keyed by id, so re-runs are
free and the process is resumable / interruptible. Output: enriched_manifest.json
(the original manifest + a `source_meta` block + possibly-filled artist/title).

This NEVER touches media files. It only reads the manifest and writes JSON.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path


# reuse the exact same parsing grammar as the organizer
sys.path.insert(0, str(Path(__file__).resolve().parent))
import organize_media as om


def source_url(source: str, sid: str) -> str | None:
  if source == "soundcloud" and sid.isdigit():
    return f"https://api.soundcloud.com/tracks/{sid}"
  if source == "youtube":
    return f"https://www.youtube.com/watch?v={sid}"
  return None


def fetch(url: str, timeout: int) -> dict | None:
  """Return the yt-dlp single-json dict, or None on any failure."""
  try:
    proc = subprocess.run(
      [
        "yt-dlp",
        "--skip-download",
        "--no-warnings",
        "--socket-timeout",
        str(timeout),
        "--dump-single-json",
        url,
      ],
      capture_output=True,
      text=True,
      timeout=timeout + 15,
    )
  except subprocess.TimeoutExpired:
    return None
  if proc.returncode != 0 or not proc.stdout.strip():
    return None
  try:
    return json.loads(proc.stdout)
  except json.JSONDecodeError:
    return None


def derive(meta: dict) -> dict:
  """Pull the fields we care about out of a yt-dlp json blob."""
  return {
    "uploader": (meta.get("uploader") or meta.get("channel") or "").strip(),
    "title": (meta.get("title") or "").strip(),
    "artist": (meta.get("artist") or "").strip(),  # often NA/empty
    "webpage_url": meta.get("webpage_url", ""),
  }


def recover_artist_title(src: dict) -> tuple[str, str, list[str]]:
  """Apply the merge rule. Returns (artist, title, featured)."""
  title = src["title"]

  # normalize source strings through the SAME unicode pipeline the filename
  # parser uses, so a source uploader like "Makay， Kindrid" (fullwidth comma)
  # is cleaned to "Makay, Kindrid" before it becomes our artist.
  def norm(s: str) -> str:
    return om.fold_fullwidth(om.fix_chars(s or "")).strip()

  base_artist = norm(src["artist"]) if src["artist"] and src["artist"] != "NA" else ""

  # 2) if the title looks like "Artist - Title", parse it with our grammar by
  #    running it through the organizer parser (fake a name with a dummy id).
  if " - " in title:
    rec = om.parse(f"{title} [0].m4a", Path(f"{title} [0].m4a"))
    return (rec.artist or base_artist, rec.title, rec.featured)

  # 3) no separator in title -> uploader is the artist; still parse the title
  #    for any inline "(feat. X)".
  rec = om.parse(f"{title} [0].m4a", Path(f"{title} [0].m4a"))
  artist = base_artist or norm(src["uploader"])
  return (artist, rec.title or title, rec.featured)


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--manifest", default=".organize/manifest.json")
  ap.add_argument("--out", default=".organize/enriched_manifest.json")
  ap.add_argument("--cache", default=".organize/enrich_cache.json")
  ap.add_argument("--timeout", type=int, default=30)
  ap.add_argument("--sleep", type=float, default=0.4, help="politeness delay between live queries")
  ap.add_argument(
    "--limit",
    type=int,
    default=0,
    help="cap live queries this run (0 = no cap); resume later",
  )
  ap.add_argument(
    "--only-unknown",
    action="store_true",
    default=True,
    help="only query files whose artist is empty (default)",
  )
  ap.add_argument(
    "--max-passes",
    type=int,
    default=3,
    help="sweeps over unresolved targets; retries transient (rate-limit) errors",
  )
  ap.add_argument(
    "--cooldown",
    type=float,
    default=20.0,
    help="base seconds to wait between retry sweeps (grows per sweep)",
  )
  args = ap.parse_args()

  recs = json.load(open(args.manifest, encoding="utf-8"))
  cache: dict = {}
  if Path(args.cache).exists():
    cache = json.load(open(args.cache, encoding="utf-8"))

  targets = [
    r
    for r in recs
    if r["kind"] == "audio"
    and (not r["artist"] if args.only_unknown else True)
    and r["source_id"]
    and r["source"] in ("soundcloud", "youtube")
  ]
  print(f"candidates to enrich : {len(targets)}")
  print(f"already cached       : {sum(1 for r in targets if r['source_id'] in cache)}")

  # Query in up to `passes` sweeps. Each sweep attempts every still-unresolved
  # target; failures (almost always transient 403 rate-limits) are left as
  # errors and retried on the next sweep after a growing cooldown. This makes
  # the rate-limit seam self-healing instead of needing manual re-runs.
  queried = 0
  passes = max(1, args.max_passes)
  for sweep in range(passes):
    pending = [
      r for r in targets if not (r["source_id"] in cache and "error" not in cache[r["source_id"]])
    ]
    if not pending:
      break
    if sweep:
      cooldown = args.cooldown * sweep
      print(f"  sweep {sweep + 1}/{passes}: {len(pending)} pending, cooling down {cooldown}s")
      time.sleep(cooldown)
    for r in pending:
      sid = r["source_id"]
      if args.limit and queried >= args.limit:
        break
      url = source_url(r["source"], sid)
      if not url:
        cache[sid] = {"error": "no-url"}
        continue
      meta = fetch(url, args.timeout)
      if meta is None:
        cache[sid] = {"error": "fetch-failed"}
        time.sleep(args.sleep * 2)  # back off harder after a failure
      else:
        cache[sid] = derive(meta)
        time.sleep(args.sleep)
      queried += 1
      if queried % 20 == 0:
        json.dump(
          cache,
          open(args.cache, "w", encoding="utf-8"),
          indent=2,
          ensure_ascii=False,
        )
        print(f"  ... {queried} queried (checkpoint)")

  json.dump(cache, open(args.cache, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
  print(f"live queries this run: {queried}")

  # merge cache -> enriched manifest
  filled = failed = 0
  for r in recs:
    sid = r.get("source_id")
    src = cache.get(sid)
    if not src or "error" in (src or {}):
      if r["kind"] == "audio" and not r["artist"]:
        failed += 1
      continue
    r["source_meta"] = src
    if not r["artist"]:
      artist, title, feat = recover_artist_title(src)
      if artist:
        r["artist"] = artist
        # compute the grouping key so recovered tracks group like the
        # rest of the library (was missing -> recovered tracks lost
        # albumartist grouping entirely).
        r["artist_primary"] = om.primary_artist(artist)
        if title:
          r["title"] = title
        # union featured
        for f in feat:
          if f and f not in r["featured"]:
            r["featured"].append(f)
        r["confidence"] = "recovered"
        r["needs_review"] = False
        r["notes"].append(f"artist recovered from {r['source']} id {sid}")
        # NOTE: dest_relpath is intentionally NOT recomputed — tagging
        # writes into the files in place (/var/lib/media); the artist
        # folder layout from the organize step is left as-is.
        filled += 1

  json.dump(recs, open(args.out, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
  still_unknown = sum(1 for r in recs if r["kind"] == "audio" and not r["artist"])
  print(f"artists recovered    : {filled}")
  print(f"still unknown        : {still_unknown}  (fetch-failed: {failed})")
  print(f"enriched manifest    : {args.out}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
