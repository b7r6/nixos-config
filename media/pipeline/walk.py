#!/usr/bin/env python3
"""
walk.py — graph walk over the artist collaboration graph.

Nodes = artists (by SoundCloud profile). Edges = collaborations (co-credits and
features parsed from track metadata). We start from GC-root profiles and expand:
each iteration discovers a frontier profile's sets, and any NEW collaborator
profiles found become the next frontier. We stop when an iteration adds no new
profiles AND surfaces no new parser seams (a fixpoint).

This script is the DISCOVERY half (no downloads): given a set of profile URLs,
it lists their sets and returns candidate playlist URLs + the collaborator
profiles it can resolve. State (seen profiles, frontier) lives in walk_state.json.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ORG = Path(__file__).resolve().parent
STATE = ORG / "walk_state.json"


def ytdlp_json(args: list[str], timeout: int = 90) -> list[dict]:
  try:
    p = subprocess.run(
      [
        "yt-dlp",
        "--flat-playlist",
        "--dump-json",
        "--socket-timeout",
        "20",
        *args,
      ],
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


def load_state() -> dict:
  if STATE.exists():
    return json.load(open(STATE, encoding="utf-8"))
  return {
    "seen_profiles": [],
    "frontier": [],
    "iteration": 0,
    "all_candidate_urls": [],
  }


def save_state(s: dict) -> None:
  json.dump(s, open(STATE, "w", encoding="utf-8"), indent=2, ensure_ascii=False)


def discover_sets(profile: str) -> list[dict]:
  """Return [{title,url}] for a profile's /sets page."""
  sets = ytdlp_json([f"{profile.rstrip('/')}/sets"])
  return [{"title": s.get("title"), "url": s.get("url")} for s in sets if s.get("url")]


def main() -> int:
  # usage: walk.py discover <profile1> <profile2> ...
  cmd = sys.argv[1] if len(sys.argv) > 1 else "discover"
  profiles = sys.argv[2:]
  state = load_state()

  if cmd == "discover":
    new_candidates = []
    for prof in profiles:
      if prof in state["seen_profiles"]:
        print(f"  (seen) {prof}")
        continue
      sets = discover_sets(prof)
      print(f"  {prof} -> {len(sets)} sets")
      for s in sets:
        new_candidates.append({"profile": prof, **s})
      state["seen_profiles"].append(prof)
    state["all_candidate_urls"] = state.get("all_candidate_urls", []) + new_candidates
    save_state(state)
    # write just this round's candidates for the downloader
    json.dump(
      new_candidates,
      open(ORG / "round_candidates.json", "w", encoding="utf-8"),
      indent=2,
      ensure_ascii=False,
    )
    print(f"\nnew candidate sets this round: {len(new_candidates)}")
    print(f"total seen profiles: {len(state['seen_profiles'])}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
