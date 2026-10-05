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
