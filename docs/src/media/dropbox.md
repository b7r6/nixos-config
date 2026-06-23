# dropbox — shareable URLs for private files (the "secret gist" model)

From `modules/nixos/dropbox.nix` under `hyper-modern-nixos.dropbox` +
`packages/drop`. **Off by default.** Live on `guccimane`.

A primitive for "hey, this file is at this URL" without making anything
crawlable or public-by-listing. Closest mental model: **GitHub secret gists** —
technically reachable by URL, but unguessable, so it's effectively private.

## Current state (deployed)

- **R2 bucket `straylight-drop`** created; rclone-mounted at `/mnt/r2/drop` via
  the `hyper-modern-nixos.rcloneMount.mounts.drop` entry (gated by
  `dropbox.mountEnable`). The mount maps **1:1** to the bucket, so dropping a
  file = it's at the matching key instantly.
- **`drop` CLI** (`packages/drop`, installed on guccimane): `drop <file>` copies
  under a fresh 128-bit base32 token dir and prints the URL; `-t <tok>` adds to
  an existing drop (mini-gist); `--ls` / `--rm <tok>` list / revoke. No creds in
  the tool — it rides the mount's agenix R2 creds.
- **Staged on the tailnet for now.** Rather than flip R2 public access (the
  "truly public" step, deferred to a coordinated DNS move), the bucket is fronted
  by **nginx on guccimane at `drop.sju1.s4.gl`** (CoreDNS resolves the `drop`
  service tag → guccimane; wildcard `*.sju1.s4.gl` cert via Njalla DNS-01).
  nginx serves the FUSE mount as a static root with **`autoindex off`** — so the
  bucket root is never listable, preserving the token-is-the-capability property.
  `hyper-modern-nixos.dropbox.domain = "drop.sju1.s4.gl"` so `drop` emits those
  URLs.

So today: `drop foo.flac` → `https://drop.sju1.s4.gl/d/<token>/foo.flac`,
reachable by anyone on the tailnet/LAN. To **graduate to public**: enable R2
public access (needs a Cloudflare API token with `Workers R2 Storage:Edit`) or
bind a public custom domain, then repoint `dropbox.domain`. Done "all at once"
with the rest of the public-DNS cutover.

## Model (design rationale)

- **Public R2 bucket** (`straylight-drop`) exposed via a **custom domain**
  `drop.s4.gl` (Cloudflare-managed; real CDN + TLS, no server in the path).
- **Unguessable random-key prefix** per drop: a 128-bit token directory, so the
  object key is `d/<token>/<filename>`.
  - R2 public access does **not** allow bucket listing, so without the token
    nobody can enumerate or guess a drop. The token IS the capability.
- **Permanent by default** (gist-like). Expiry/revocation is "delete the object"
  (or use the presigned-URL path for time-boxed links — see Variants).

Result: `drop somefile.flac` →
`https://drop.s4.gl/d/9f3a2c…e1/somefile.flac` — paste anywhere, anyone can fetch,
nobody can browse.

## Why a random *directory*, not a random filename

Keeping the human filename intact (`…/d/<token>/Notaker - Melting Bismuth.flac`)
means the download lands with a sane name and the URL is self-describing, while
the secrecy lives entirely in the `<token>` path segment. One token can also
hold multiple files (a mini-gist): `…/d/<token>/{cover.jpg,track.flac}`.

## The /mnt/r2 view

The share bucket is also rclone-mounted, so dropping = a file copy into the FUSE
mount; the matching URL is live immediately (no separate upload step). Local
layout under the existing `/mnt/r2` base:

```
/mnt/r2/
├── common/                      # SHARED across fleet (existing; 5s dir-cache)
│   └── drop/                    # ← the dropbox staging view (any host can drop)
│       └── d/
│           └── <token>/         # one drop = one random-token dir
│               └── <filename>
└── guccimane/                   # per-host (existing; 12h dir-cache)
```

NOTE: `/mnt/r2/common` is backed by the `host-mount` bucket, which is NOT the
public `straylight-drop` bucket. Two clean options for wiring the mount:

1. **Separate mount for the share bucket** (preferred): add an
   `rcloneMount.mounts.drop` entry pointing at `straylight-drop:` so
   `/mnt/r2/drop/` maps 1:1 to the public bucket. Dropping a file there is
   instantly at `https://drop.s4.gl/<same key>`. Cleanest URL↔path mapping.
2. Reuse `common/drop/` and have the `drop` tool `rclone copy` to the public
   bucket. More moving parts; skip in favour of (1).

Proposed mount (sketch, for the rclone-mount module's `mounts` escape hatch):

```nix
hyper-modern-nixos.rcloneMount.mounts.drop = {
  remote   = "straylight-drop:";      # the public share bucket
  where    = "/mnt/r2/drop";
  readOnly = false;                    # we write drops here
  # short dir-cache: drops should appear/disappear promptly
  extraArgs = [ "--vfs-cache-mode=writes" "--dir-cache-time=5s" "--s3-no-check-bucket" ];
};
```

So the final interaction surface:

```
/mnt/r2/drop/                    # == straylight-drop bucket == drop.s4.gl/
└── d/
    └── <token>/<filename>       # == https://drop.s4.gl/d/<token>/<filename>
```

## The `drop` CLI (sketch)

```
drop <path>...                   # copy file(s) under a fresh random token, print URL(s)
drop --token <tok> <path>...     # add to an existing drop (mini-gist)
drop --ls                        # list your drops (reads the mount, not the bucket API)
drop --rm <token>                # delete a drop (revoke the share)
```

- token = `head -c16 /dev/urandom | base32` (lowercased, ~26 url-safe chars).
- URL = `https://${DROP_DOMAIN}/d/<token>/<urlencoded filename>`.
- Writes go through the `/mnt/r2/drop` FUSE mount (no aws creds in the tool;
  the mount already holds them via agenix).

## Variants (later, if wanted)

- **Expiring links:** keep a second PRIVATE bucket + `rclone link --expire 24h`
  for time-boxed shares (`drop --expiring`). Genuinely private + revocable.
- **Content-addressed dedupe:** key by `sha256(file)` instead of random token —
  same file → same URL, natural dedupe. Loses per-share revocation though.
- **Index page:** a generated `index.html` per token dir for a prettier landing
  page (opt-in; the bucket stays non-listable at the root).

## Provisioning checklist (Cloudflare-side, NOT yet done)

1. Create R2 bucket `straylight-drop`.
2. Enable public access; attach custom domain `drop.s4.gl` (Cloudflare DNS).
3. Mint an R2 API token scoped to this bucket; add to the rclone agenix config
   as a `straylight-drop` remote.
4. Wire `rcloneMount.mounts.drop` (above) + ship the `drop` CLI.
5. (Optional) Cloudflare WAF/rate-limit + a `robots.txt` deny at the domain
   root for belt-and-suspenders against crawlers.
```
