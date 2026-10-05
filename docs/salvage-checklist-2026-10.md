# Fleet sell-off salvage checklist — 2026-10

Status as of 2026-10-05. Verification + triage done read-only over ssh;
copies landed in shannon `~/salvage-2026-10-05/` (inside /home → swept to R2
by hourly restic).

## Verified intact (checked 2026-10-05)

- **straylight-archive R2 bucket**: ~20.9 GiB / 5,113 objects (media, photos,
  conversations, papers, writing, artifacts, data, books). Forge separately in
  `straylight-forge-mirror`.
- **Forge → GitHub**: all 33 Forgejo repos have `orbital-<org>-<repo>` private
  mirrors in `hypermodern-src`; 5-repo SHA sample matches; no divergence since
  the 2026-10-04 mirror. (radix-orbital: default-branch setting differs,
  content identical.)
- **nixos-config salvage refs**: 15 `salvage/*` branches on b7r6/nixos-config,
  including 4 branch tips + 5 stashes that existed ONLY on watchtower/uv disks
  until 2026-10-05.

## Copied to shannon 2026-10-05 (~34G)

From watchtower: `~/src/watchtower` (no remote, uncommitted — the only copy),
`~/src/straylight` (dirty tree), `~/guccimane-src/fxy-0x01` (dirty),
`~/shimmer-hedge/no-remote-repos/`, `~/shimmer-hedge/src/` (4.6G — includes
rh-sol + archives), wan-spike scripts/notes/outputs (weights excluded).
From guccimane: `/var/backup/justin/{src,jpyxal,fxy-nix,.atuin,straylight,desktop}`
(root-only home backup from 2026-02; no evidence it was duplicated anywhere).

## Ultraviolence sweep (2026-10-05 evening, drop-out-tonight check)

- **26 git repos → GitHub** `hypermodern-src/salvage-uv-*` (private): slide-rule
  (never-pushed Lean proofs), nix-0x02 (39 unpushed commits; was a SHALLOW
  clone — unshallowed from NixOS/nix before push, ditto salvage-uv-nix),
  latent, villa-straylight, weyl-std, render-gateway, s4-gauge, all trash/*
  repos, and the rest of the no-remote/unpushed set. Plus trash plain dirs +
  straylight.tar.gz → shannon `~/salvage-2026-10-05/uv-git/`.
- **Dirty-tree patches + untracked tarballs** for the 11 heavy dirty repos →
  shannon `~/salvage-2026-10-05/uv-dirty/` (13G+).
- **looking-local (165G unique dataset)** → streaming to R2
  `straylight-archive/data/looking-local-uv` (rclone on uv, log at
  /tmp/rclone-looking-local.log — SLOW, verify complete before power-off).
- Transmission download dir empty; searxng/flood state nil — nothing to save.
- **Judgment pile → R2 exodus (policy: everything big-but-unverified parks in
  R2 at ~$12/mo, judged later)**: sequential rclone queues running on uv
  (`/tmp/uv-exodus.{sh,log}` → `straylight-archive/artifacts/uv-exodus/`:
  s4-gauge 69G Flux TRT engines, archive-downloads 192G, src-archives 363G,
  ACE-Step, eminem-godzilla, i-mean-it, archive-mp4, nested-home, dgx-spark,
  keeper-forge, nl-wt dirs) and watchtower (`/tmp/wt-exodus.log` →
  `artifacts/wt-exodus/`: shimmer-hedge Downloads/home/Documents/Pictures/
  Screenshots + small Downloads) and guccimane (justin .config →
  `artifacts/gucci-exodus/`). **Verify COMPLETE lines in each log before
  power-off** — ~820G total, runs overnight+. dissertation dirty files:
  review diff (repo itself pushed).
- **uv secrets to wipe**: /etc/ssh host keys, ~/.ssh (3 private keys),
  ~/.gnupg, ~/.password-store, ~/.netrc, ~/.config/gcloud.

## Drop-out-tonight verdicts (verified 2026-10-05)

- **guccimane: GO.** Media+state copied (34G), justin-backup copied (26G),
  /fxy verified all-public-HF. Remaining: wipe keys.
- **ultraviolence: GO once looking-local upload completes** (and modulo the
  judgment pile above). Remaining: wipe keys.
- Infra impact of both dropping: ClickHouse fine (no Replicated tables —
  keeper quorum loss is harmless; all-MergeTree verified), nix substitution
  fine (local replica first), NativeLink CAS ring logs errors until topology
  retag (cosmetic), SearXNG/torrents/media serving die until re-homed on
  shannon.

## MUST do before hardware leaves (manual, destructive — not automated)

- [ ] **Wipe private keys**: guccimane `/var/backup/justin/.ssh/id_ed25519`,
      watchtower `~/.ssh`, and any agenix host keys (`/etc/ssh/ssh_host_*`)
      on every sold machine. Host keys are agenix recipients.
- [ ] **shimmer last power-on**: `~/Downloads` holds the RH paper
      (`a_man_a_plan_rewritten_v2*.pdf`) and TenLaws Lean files per notes —
      confirm copies exist elsewhere (TenLaws(4).lean also on shannon).
- [ ] Owner judgment pile (~65G, not copied): watchtower
      `~/shimmer-hedge/{Downloads,home,Documents,Pictures,Screenshots}`,
      `~/Downloads` small files, browser profiles, `/var/backup/justin/.config` (18G).
- [ ] Full-disk wipe of all sold machines after final check
      (`blkdiscard`/`nvme format`).

## Safe to abandon (~650G, all re-derivable)

watchtower `~/.cache` (124G), wan-spike weights/venv (165G), `~/models` (26G),
nvidia-sdk trees (224G), ISO/gguf Downloads (~40G); guccimane `/fxy` (447G —
public HF hub models only, verified nothing custom).

## Found & fixed during the drill

- **Litestream → R2 was dead** (`straylight-litestream` bucket didn't exist;
  NoSuchBucket on every sync). Bucket created, service restarted, replica
  syncing again 2026-10-05 16:28 EDT. Unknown how long it was down — Kanidm
  data-loss window was covered only by restic during that period.
