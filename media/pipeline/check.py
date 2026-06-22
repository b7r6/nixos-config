import json


recs = json.load(open(".organize/manifest.json"))
by = {r["source_name"]: r for r in recs}


def show(name):
  r = by.get(name)
  if not r:
    print("MISSING:", name)
    return
  print(f"  src : {name}")
  print(f"  out : {r['dest_relpath']}")
  print(
    f"        artist={r['artist']!r} title={r['title']!r} "
    f"feat={r['featured']} remixer={r['remixer']!r} mix={r['mix_type']!r}"
  )
  if r["tags"]:
    print(f"        tags={r['tags']}")
  print()


names = [
  "Notaker - Into The Light (feat. Karra) [567990843].m4a",
  "Notaker & Declan James feat. Karra - Who I Am (Extended Mix) [345145025].m4a",
  "ATLiens - Fading Out (feat. Sara Skinner) [Luca Lush Remix] [709876933].m4a",
  "deadmau5 - Raise Your Weapon (Hex Cougar Remix) [299942162].m4a",
  "Autumn Fog (w\u29f8 Syberlilly) [Slowed & Reverbed] [1740791433].m4a",
  "\U0001f499 Just Connor - Down (free download in desc, thx for your support)\U0001f499 [568798776].m4a",
  "T-Mass - Language For Now (ft. Skrillex, Diplo, Justin Bieber, Porter Robinson, Deadmau5 & Kaskade) [212826810].m4a",
  "Trentem\u00f8ller\uff1a Moan (official music video) [C4RaGppX-sU].mkv",
  "Best of Deadmau5 [t2rwcvMRvZs].webm",
  "blackbeatles [294643401].mp3",
  "\U0001d47b \U0001d479 \U0001d468 \U0001d475 \U0001d47a \U0001d469 \U0001d46c \U0001d475 \U0001d47b [653689172].m4a",
  "A$AP Rocky - Telephone Calls (Ft. Tyler The Creator & Playboi Carti) [Download In Description] [290435593].m4a",
]
for n in names:
  show(n)
