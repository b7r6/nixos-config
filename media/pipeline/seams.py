#!/usr/bin/env python3
"""
seams.py — detect parser/enricher EDGE CASES (seams) in an enriched manifest.

Run after enrichment on a staging batch. Prints a categorized report and exits
nonzero if any seam is found, so the graph-walk loop knows whether it reached a
fixpoint (zero new seams) or must harden + iterate.

Seam categories:
  - empty_artist        : audio track still has no artist after enrichment
  - residual_unicode    : fullwidth/odd chars that should have been normalized
  - residual_promo      : promo cruft left in title (*..*, free dl, out now, ...)
  - missing_primary     : has artist but no artist_primary (grouping would break)
  - suspicious_primary  : primary looks wrong (1-2 chars, or trailing 'feat'/'&')
  - casing_collision    : primary collides with another primary only by case
"""

from __future__ import annotations

import json
import re
import sys
from collections import defaultdict


PROMO = re.compile(r"\*[^*]*\*|\bfree\s*(dl|download)\b|\bout now\b|video in desc", re.IGNORECASE)

# Source IDs that are genuinely irreducible (deleted/private at source, so no
# enrichment can recover them). NOT parser seams; excluded from the fixpoint test.
IRREDUCIBLE = {"279259366"}  # 'feels' — deleted from SoundCloud


def has_weird_unicode(s: str) -> bool:
  for ch in s:
    # fullwidth forms (FF00-FFEF) or unhandled big-solidus class
    if "\uff00" <= ch <= "\uffef" or ch in "\u29f8\u29f9":
      return True
    # superscript/letterlike that NFKC would change in a name field
  return False


def main() -> int:
  path = sys.argv[1] if len(sys.argv) > 1 else ".organize/staging_enriched.json"
  recs = json.load(open(path, encoding="utf-8"))
  audio = [r for r in recs if r.get("kind") == "audio"]

  seams: dict[str, list[str]] = defaultdict(list)

  for r in audio:
    if r.get("source_id") in IRREDUCIBLE:
      continue
    a = r.get("artist", "")
    t = r.get("title", "")
    p = r.get("artist_primary", "")
    tag = f"[{r.get('source')}:{r.get('source_id')}] {t!r}"

    if not a:
      seams["empty_artist"].append(tag)
    if has_weird_unicode(a) or has_weird_unicode(t):
      seams["residual_unicode"].append(f"{tag} a={a!r}")
    if PROMO.search(t):
      seams["residual_promo"].append(f"{tag}")
    if a and not p:
      seams["missing_primary"].append(f"{tag} a={a!r}")
    if p and (len(p) <= 1 or re.search(r"\b(feat|ft|&|x|with)$", p, re.IGNORECASE)):
      seams["suspicious_primary"].append(f"{p!r} <- a={a!r}")

  # casing collisions among primaries
  low = defaultdict(set)
  for r in audio:
    p = r.get("artist_primary", "")
    if p:
      low[p.lower()].add(p)
  for k, v in low.items():
    if len(v) > 1:
      seams["casing_collision"].append(str(sorted(v)))

  total = sum(len(v) for v in seams.values())
  print(f"=== seam report ({path}) ===")
  print(f"audio tracks: {len(audio)}")
  for cat in [
    "empty_artist",
    "residual_unicode",
    "residual_promo",
    "missing_primary",
    "suspicious_primary",
    "casing_collision",
  ]:
    items = seams.get(cat, [])
    print(f"  {cat:20} : {len(items)}")
    for it in items[:8]:
      print(f"      - {it}")
  print(f"\nTOTAL SEAMS: {total}")
  return 1 if total else 0


if __name__ == "__main__":
  sys.exit(main())
