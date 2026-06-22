#!/usr/bin/env python3
"""
discover.py — for each seed artist profile, list their SoundCloud sets
(playlists/EPs/albums) WITHOUT downloading. Emits a candidate list of playlist
URLs we can later pull. Pure read: flat-playlist json only.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ORG = Path(__file__).resolve().parent


def flat(url: str, timeout: int = 60) -> list[dict]:
  try:
    p = subprocess.run(
      ["yt-dlp", "--flat-playlist", "--dump-json", "--socket-timeout", "20", url],
      capture_output=True,
      text=True,
      timeout=timeout,
    )
  except subprocess.TimeoutExpired:
    return []
  out = []
  for line in p.stdout.splitlines():
    try:
      out.append(json.loads(line))
    except json.JSONDecodeError:
      pass
  return out


def main() -> int:
  profiles = json.load(open(ORG / "profiles.json", encoding="utf-8"))
  # one profile per unique base URL (artist-name variants collapse here)
  bases = sorted(set(profiles.values()))
  limit = int(sys.argv[1]) if len(sys.argv) > 1 else len(bases)

  candidates: list[dict] = []
  for base in bases[:limit]:
    sets = flat(f"{base}/sets")
    print(f"{base}/sets -> {len(sets)} sets")
    for s in sets:
      candidates.append(
        {
          "profile": base,
          "title": s.get("title"),
          "url": s.get("url"),
        }
      )
  json.dump(
    candidates,
    open(ORG / "candidates.json", "w", encoding="utf-8"),
    indent=2,
    ensure_ascii=False,
  )
  print(f"\ntotal candidate playlists: {len(candidates)}")
  print(f"written: {ORG / 'candidates.json'}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
