#!/usr/bin/env python3
"""
organize_media.py — parse rich metadata out of messy download filenames and
copy media into a consistent hyphenated layout.

Embedded tags in these files are empty, so the *filename* is the only metadata
source. This script extracts a structured record per file (artist, title,
featured artists, remixer, mix type, source id) and emits:

  - manifest.json : one rich record per file (input for downstream cleanup)
  - a copied tree under <dest> with normalized hyphenated names

It NEVER modifies originals. Default is a dry run; pass --apply to copy.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import unicodedata
from dataclasses import asdict, dataclass, field
from pathlib import Path


# ---------------------------------------------------------------------------
# extension / kind tables
# ---------------------------------------------------------------------------

AUDIO_EXTS = {".m4a", ".mp3", ".flac", ".wav", ".opus", ".aac", ".ogg"}
VIDEO_EXTS = {".mkv", ".mp4", ".webm", ".mov", ".avi"}

# ---------------------------------------------------------------------------
# unicode normalization: download tools substitute fs-unsafe chars
# ---------------------------------------------------------------------------

# direct character replacements (fullwidth / lookalike -> ascii)
CHAR_FIXES = {
  "\u29f8": "/",  # ⧸ big solidus  (stand-in for '/')
  "\u29f9": "\\",  # ⧹ big reverse solidus
  "\uff0f": "/",  # ／ fullwidth solidus
  "\uff3c": "\\",  # ＼ fullwidth reverse solidus
  "\uff1a": ":",  # ： fullwidth colon
  "\uff0c": ",",  # ， fullwidth comma  (artist joins: "wevlth， wevlth")
  "\uff1b": ";",  # ； fullwidth semicolon
  "\uff02": '"',  # ＂ fullwidth quote
  "\uff03": "#",  # ＃
  "\uff04": "$",  # ＄
  "\uff06": "&",  # ＆
  "\uff5c": "|",  # ｜ fullwidth vertical bar
  "\u2018": "'",
  "\u2019": "'",  # curly single quotes
  "\u201c": '"',
  "\u201d": '"',  # curly double quotes
  "\u2013": "-",
  "\u2014": "-",  # en/em dash -> hyphen
  "\u2015": "-",
}

# zero-width / BOM / control junk to drop entirely
ZERO_WIDTH = {"\ufeff", "\u200b", "\u200c", "\u200d", "\u2060"}


def fix_chars(s: str) -> str:
  out = []
  for ch in s:
    if ch in ZERO_WIDTH:
      continue
    out.append(CHAR_FIXES.get(ch, ch))
  return "".join(out)


def fold_fullwidth(s: str) -> str:
  """NFKC folds fullwidth latin/letterforms (𝑻 𝑹 𝑨..., ＡＣＥ...) to ascii."""
  return unicodedata.normalize("NFKC", s)


# ---------------------------------------------------------------------------
# id extraction:  "<stem> [<id>]"  where id is digits (SC) or 11-char (YT)
# ---------------------------------------------------------------------------

ID_RE = re.compile(r"^(?P<stem>.*?)\s*\[(?P<id>[^\[\]]+)\]\s*$")
YT_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")


def classify_source(track_id: str) -> str:
  if track_id.isdigit():
    return "soundcloud"
  if YT_ID_RE.match(track_id):
    return "youtube"
  return "unknown"


# ---------------------------------------------------------------------------
# promo / junk bracket tags to lift out of the title (kept in record.tags)
# ---------------------------------------------------------------------------

PROMO_RE = re.compile(
  r"""\b(
        free \s* (download|dl)
      | out \s* now
      | download \s+ in \s+ desc\w*
      | thx \s+ for .*
      | now \s+ available
      | buy \s* = .*
      | = \s* 320 .*
      | thissongissick\.com .*
      | stylss\.com .*
    )\b""",
  re.IGNORECASE | re.VERBOSE,
)

# Inline promo cruft wrapped in asterisks/brackets/quotes that ends up glued to
# a title, e.g. "Nowhere to Run *VIDEO IN DESCRIPTION*" or "Track 「FREE DL」".
# Stripped from the title after parsing (the bracketed-chunk path doesn't catch
# these because they're inline, not parenthetical).
INLINE_PROMO_RE = re.compile(
  r"""(
        \* [^*]* \*                       # *VIDEO IN DESCRIPTION* / *Free DL*
      | \u300c [^\u300d]* \u300d           # 「 ... 」
      | (?:video|link|out|buy) \s+ in \s+ (?:desc\w*|bio)   # video in description
      | [^\w\s]* \s* free \s* (?:download|dl) \s* [^\w\s]*  # 🌀FREE DL🌀 / **FREE DL**
      | \d+% \s* \w*productions?                            # *100%productions*
    )""",
  re.IGNORECASE | re.VERBOSE,
)

# trailing/leading separator noise left after a promo chunk is excised, e.g.
# "Fuck U All The Time | FREE DOWNLOAD" -> "Fuck U All The Time |" -> trimmed.
_SEP_EDGE_RE = re.compile(r"^[\s|/.\-–—:•]+|[\s|/.\-–—:•]+$")


def strip_inline_promo(s: str) -> str:
  cleaned = INLINE_PROMO_RE.sub(" ", s)
  cleaned = re.sub(r"\s{2,}", " ", cleaned)
  cleaned = _SEP_EDGE_RE.sub("", cleaned).strip()
  return cleaned


# mix-type vocabulary; longest first so "Original Mix" beats "Mix"
MIX_TYPES = [
  "VIP Remix",
  "Extended Mix",
  "Extended Remix",
  "Original Mix",
  "Radio Edit",
  "Radio Mix",
  "Club Mix",
  "Album Mix",
  "Dubstep Remix",
  "Remix",
  "Bootleg",
  "Flip",
  "Mashup",
  "Cover",
  "Rework",
  "Reflip",
  "Re-Flip",
  "Re-Sauce",
  "Edit",
  "VIP",
  "Mix",
]
MIX_TYPE_RE = re.compile(
  r"(?P<who>.*?)\s*\b(?P<type>" + "|".join(re.escape(m) for m in MIX_TYPES) + r")\b\.?$",
  re.IGNORECASE,
)

FEAT_RE = re.compile(r"\b(?:feat\.?|ft\.?|featuring)\b\.?\s*", re.IGNORECASE)
WITH_RE = re.compile(r"^\s*(?:w/|with)\s+", re.IGNORECASE)


# ---------------------------------------------------------------------------
# record
# ---------------------------------------------------------------------------


@dataclass
class Record:
  source_path: str
  source_name: str
  source_id: str = ""
  source: str = "unknown"
  ext: str = ""
  kind: str = "other"

  artist: str = ""
  artist_primary: str = ""  # first artist before any &/,/x join — for grouping
  title: str = ""
  featured: list[str] = field(default_factory=list)
  remixer: str = ""
  mix_type: str = ""
  tags: list[str] = field(default_factory=list)

  dest_name: str = ""
  dest_relpath: str = ""

  confidence: str = "low"
  needs_review: bool = True
  notes: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# parsing
# ---------------------------------------------------------------------------


def split_parens(text: str) -> tuple[str, list[str]]:
  """Return (text_without_parens, [paren_contents...]) handling () and []."""
  chunks: list[str] = []

  def grab(s: str, op: str, cl: str) -> str:
    out, depth, buf = [], 0, []
    for ch in s:
      if ch == op:
        depth += 1
        if depth == 1:
          buf = []
          continue
      if ch == cl and depth > 0:
        depth -= 1
        if depth == 0:
          chunks.append("".join(buf).strip())
          continue
      if depth > 0:
        buf.append(ch)
      else:
        out.append(ch)
    return "".join(out)

  text = grab(text, "(", ")")
  text = grab(text, "[", "]")
  return re.sub(r"\s{2,}", " ", text).strip(" -"), [c for c in chunks if c]


def classify_chunk(chunk: str, rec: Record) -> None:
  """Route a parenthetical chunk into featured / remixer / mix_type / tags."""
  c = chunk.strip()
  if not c:
    return

  if PROMO_RE.search(c):
    rec.tags.append(c)
    return

  # "w/ X" collaborator
  if WITH_RE.search(c):
    who = WITH_RE.sub("", c).strip()
    if who:
      rec.featured.append(who)
    return

  # "feat. X" / "ft. X"
  if FEAT_RE.search(c):
    who = FEAT_RE.sub("", c).strip(" )(")
    for name in re.split(r"\s*(?:,|&|/| x )\s*", who):
      name = name.strip()
      if name:
        rec.featured.append(name)
    return

  # "<who> Remix" / "<who> Edit" / "Original Mix" ...
  m = MIX_TYPE_RE.match(c)
  if m:
    rec.mix_type = canon_mix_type(m.group("type"))
    who = m.group("who").strip()
    # strip a feat. embedded in the remixer credit
    if FEAT_RE.search(who):
      who = FEAT_RE.sub("", who).strip()
    if who and who.lower() not in (
      "original",
      "extended",
      "radio",
      "club",
      "album",
    ):
      rec.remixer = who
    return

  # leftover: keep as a tag for the cleanup squad
  rec.tags.append(c)


def canon_mix_type(t: str) -> str:
  t = t.strip().lower()
  table = {
    "remix": "Remix",
    "vip remix": "VIP Remix",
    "vip": "VIP",
    "bootleg": "Bootleg",
    "flip": "Flip",
    "mashup": "Mashup",
    "cover": "Cover",
    "rework": "Rework",
    "reflip": "Reflip",
    "re-flip": "Reflip",
    "re-sauce": "Re-Sauce",
    "edit": "Edit",
    "mix": "Mix",
    "original mix": "Original Mix",
    "extended mix": "Extended Mix",
    "extended remix": "Extended Remix",
    "radio edit": "Radio Edit",
    "radio mix": "Radio Mix",
    "club mix": "Club Mix",
    "album mix": "Album Mix",
    "dubstep remix": "Dubstep Remix",
  }
  return table.get(t, t.title())


def parse(name: str, path: Path) -> Record:
  ext = path.suffix.lower()
  kind = "audio" if ext in AUDIO_EXTS else "video" if ext in VIDEO_EXTS else "other"
  rec = Record(
    source_path=str(path),
    source_name=name,
    ext=ext,
    kind=kind,
  )

  stem = name[: -len(path.suffix)] if path.suffix else name
  stem = fold_fullwidth(fix_chars(stem)).strip()

  # extract [id]
  m = ID_RE.match(stem)
  if m:
    rec.source_id = m.group("id").strip()
    rec.source = classify_source(rec.source_id)
    stem = m.group("stem").strip()
  else:
    rec.notes.append("no [id] found")

  # pull out parenthetical/bracket chunks before splitting artist/title
  core, chunks = split_parens(stem)
  for ch in chunks:
    classify_chunk(ch, rec)

  # artist - title split FIRST (only on the FIRST ' - ').
  # Done before inline-feat handling so a "feat." appearing inside the
  # artist credit (e.g. "A & B feat. C - Title") does not eat the title.
  if " - " in core:
    artist, title = core.split(" - ", 1)
    rec.artist = artist.strip()
    rec.title = title.strip()
    rec.confidence = "high"
    rec.needs_review = False
  else:
    rec.title = core.strip()
    rec.notes.append("no ' - ' separator; artist unknown (uploader-as-artist?)")
    rec.confidence = "low"
    rec.needs_review = True

  # inline "feat." can appear in EITHER the artist or the title; pull names
  # out of both and reduce each field to the part before the feat marker.
  for fieldname in ("artist", "title"):
    val = getattr(rec, fieldname)
    if val and FEAT_RE.search(val):
      parts = FEAT_RE.split(val, maxsplit=1)
      setattr(rec, fieldname, parts[0].strip())
      feat_tail = parts[-1].strip(" )(")
      for nm in re.split(r"\s*(?:,|&|/| x )\s*", feat_tail):
        nm = nm.strip()
        if nm:
          rec.featured.append(nm)

  # dedupe featured, drop empties
  seen = set()
  rec.featured = [
    f for f in rec.featured if f and (f.lower() not in seen and not seen.add(f.lower()))
  ]

  rec.title = strip_inline_promo(rec.title)

  if not rec.title:
    rec.notes.append("empty title after parsing")
    rec.confidence = "low"
    rec.needs_review = True

  rec.artist_primary = primary_artist(rec.artist)

  build_dest(rec)
  return rec


# Split an artist credit on the common collaboration joiners and return the
# FIRST name — the "primary" artist used for library grouping (albumartist) so
# "Hex Cougar & Acyan", "Hex Cougar, Pauline Herr & ..." all group under
# "Hex Cougar" instead of fragmenting into a separate artist per collab.
# Fullwidth comma is already normalized to ',' upstream (CHAR_FIXES).
_ARTIST_JOIN_RE = re.compile(
  r"\s*(?:,|&|/|;|\bx\b|\bX\b|\bvs\.?\b|\bwith\b|\bpres\.?\b|\bpresents\b)\s*",
  re.IGNORECASE,
)

# Acts whose NAME contains a joiner char (& / x / vs) and must NOT be split.
# Syntactic rules can't tell "Above & Beyond" (one act) from "Kaskade & deadmau5"
# (two artists), so we keep a small allowlist. Match is case-insensitive prefix:
# if the credit starts with one of these, the primary IS that full name.
_ARTIST_NO_SPLIT = [
  "Above & Beyond",
  "Hall & Oates",
  "Simon & Garfunkel",
  "Above and Beyond",
]


def primary_artist(artist: str) -> str:
  if not artist:
    return ""
  low = artist.lower()
  for name in _ARTIST_NO_SPLIT:
    if low.startswith(name.lower()):
      return name
  first = _ARTIST_JOIN_RE.split(artist, maxsplit=1)[0].strip()
  return first or artist.strip()


# ---------------------------------------------------------------------------
# destination naming + layout
# ---------------------------------------------------------------------------

INVALID_FS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def sanitize(s: str) -> str:
  s = INVALID_FS.sub("", s)
  s = re.sub(r"\s{2,}", " ", s).strip(" .")
  return s


def build_dest(rec: Record) -> None:
  parts: list[str] = []
  if rec.artist:
    parts.append(rec.artist)
  if rec.title:
    parts.append(rec.title)
  base = " - ".join(parts) if parts else (rec.title or "Unknown")

  extras = ""
  if rec.featured:
    extras += f" (feat. {', '.join(rec.featured)})"
  if rec.remixer and rec.mix_type:
    extras += f" ({rec.remixer} {rec.mix_type})"
  elif rec.mix_type:
    extras += f" ({rec.mix_type})"
  elif rec.remixer:
    extras += f" ({rec.remixer} Remix)"

  id_part = f" [{rec.source_id}]" if rec.source_id else ""
  fname = sanitize(base + extras) + id_part + rec.ext
  rec.dest_name = fname

  if rec.artist and not rec.needs_review:
    folder = sanitize(rec.artist) or "_unsorted"
  else:
    folder = "_unsorted"
  rec.dest_relpath = str(Path(folder) / fname)


# ---------------------------------------------------------------------------
# driver
# ---------------------------------------------------------------------------


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--src", default=".", help="source directory (default: cwd)")
  ap.add_argument("--dest", default="organized", help="destination tree root")
  ap.add_argument("--manifest", default="manifest.json")
  ap.add_argument("--apply", action="store_true", help="actually copy files")
  args = ap.parse_args()

  src = Path(args.src).resolve()
  dest = Path(args.dest).resolve()

  files = sorted(
    p for p in src.iterdir() if p.is_file() and p.suffix.lower() in (AUDIO_EXTS | VIDEO_EXTS)
  )

  records: list[Record] = [parse(p.name, p) for p in files]

  # collision detection on dest_relpath
  seen: dict[str, int] = {}
  for r in records:
    seen[r.dest_relpath] = seen.get(r.dest_relpath, 0) + 1
  collisions = {k for k, v in seen.items() if v > 1}
  for r in records:
    if r.dest_relpath in collisions:
      r.notes.append("dest path collision")
      r.needs_review = True

  manifest = [asdict(r) for r in records]
  Path(args.manifest).write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8"
  )

  hi = sum(1 for r in records if r.confidence == "high")
  review = sum(1 for r in records if r.needs_review)
  n_remix = sum(1 for r in records if r.mix_type)
  n_feat = sum(1 for r in records if r.featured)

  print(f"files parsed     : {len(records)}")
  print(f"high confidence  : {hi}")
  print(f"needs review     : {review}")
  print(f"with remixer/mix : {n_remix}")
  print(f"with featured    : {n_feat}")
  print(f"dest collisions  : {len(collisions)}")
  print(f"manifest written : {args.manifest}")

  if not args.apply:
    print("\n[dry run] no files copied. re-run with --apply to copy.")
    return 0

  copied = 0
  for r in records:
    target = dest / r.dest_relpath
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
      r.notes.append("target existed; skipped")
      continue
    shutil.copy2(r.source_path, target)
    copied += 1
  print(f"\ncopied {copied} files into {dest}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
