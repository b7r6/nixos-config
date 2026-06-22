# State & backup model

How mutable state is laid out on a host, what survives a reboot, and what is
backed up — driven by **one** classification per service rather than three
parallel hand-maintained lists.

## The problem

Three separate concerns keep asking the same question — "is this data
precious?":

1. **Filesystem layout** — `/var/lib` vs `/srv` vs `/opt`.
2. **Impermanence** — which paths survive an ephemeral-root reboot
   (`environment.persistence."/persist".directories`).
3. **Backups** — which paths restic ships to R2 (`backup.paths`).

Maintained independently they drift, and the drift is silent until a restore
fails or a reboot eats data. They are really **one decision** seen three ways.

## The model: one `stateClass` per service

Every service that holds state declares its state directory **once**, with a
class. Layout stays **`/var/lib/<service>`-native** (no `dataDir` overrides — we
keep systemd's `StateDirectory=` sandboxing and match every upstream module).
The class drives both the impermanence persist-list and the restic paths:

| Class | Survives reboot (impermanence)? | Backed up (restic → R2)? | Examples |
| --- | --- | --- | --- |
| `authoritative` | yes | **yes** | postgres dumps, Forgejo repos, registry manifests |
| `reconstructible` | yes | **no** | atticd chunk cache, nativelink CAS (truth already on R2 / re-derivable) |
| `ephemeral` | no | no | build scratch, `/tmp`, re-fetchable caches |

- **authoritative** → persisted **and** backed up. Irreplaceable, app-managed.
- **reconstructible** → persisted (so a reboot doesn't force a slow refetch) but
  **not** backed up — the authoritative copy already lives in R2 (attic/nativelink
  chunk stores) or is re-derivable. Paying R2 to back up a cache is waste.
- **ephemeral** → neither. Wiped on reboot by design.

This makes the impermanence persist-list and the restic backup-list **derived
views of the same declaration**, so they cannot drift.

## Why `/var/lib`-native (not `/srv`)

On NixOS, `/var/lib/<service>` is where `StateDirectory=` / `tmpfiles` / every
upstream service module puts state. Relocating to `/srv` means overriding
`dataDir`/`StateDirectory` on every module and losing the auto-ownership +
`ProtectSystem` sandboxing systemd gives you for free. `/opt` is reserved for
FHS-hostile third-party blobs (we have exactly one: `/opt/rocm`). Once layout is
**path-driven by `stateClass`**, the directory name stops carrying the
backup/persist semantics — the class does — so there's no reason to deviate from
the grain.

## Impermanence interaction

When impermanence flips on (planned, once netboot + DNS land), the root is wiped
each boot and only the persist-list survives. Because the persist-list is derived
from `stateClass`, turning impermanence on is a **switch flip, not a rework**.

One sharp edge the model handles: a service's **backup staging dir** (e.g. the
postgres dump output) must itself be `authoritative` — persisted **and** backed
up — or a reboot between "dump written" and "restic ran" silently loses it.

## PostgreSQL: logical dumps now, PITR seam later

This homelab is a rehearsal for a real bare-metal fleet, so postgres backup is
staged the way you'd stage it in production:

- **Now — logical dumps.** A timer runs `pg_dumpall` (or per-db `pg_dump`) to
  `/var/backup/postgres/*.sql.zst` (an `authoritative` path). restic backs up that
  dir. The **dump is the correct restic source** — never back up a live cluster's
  data files (`/var/lib/postgresql`), which is corruption-prone and version-locked.
  Logical dumps also restore **across PG majors**, which matters when hosts get
  rebuilt.
- **Later — PITR.** The module exposes the option surface for WAL archiving +
  base backups to R2 (point-in-time recovery, RPO of seconds). It's a flip-on
  capability, not a rewrite — turn it on when a DB holds data that can't tolerate
  a day of loss, and after a restore runbook is written and tested.

## Service tiering (current + planned)

| Service | State | Class |
| --- | --- | --- |
| postgres (dumps) | `/var/backup/postgres` | `authoritative` |
| postgres (cluster) | `/var/lib/postgresql` | persisted, **not** restic'd (dumps are the backup source) |
| atticd | `/var/lib/atticd` (local chunk tier) | `reconstructible` (R2 holds the chunks) |
| nativelink | `/var/lib/nativelink` (CAS) | `reconstructible` (R2-backed / re-derivable) |
| Forgejo | `/var/lib/forgejo/repositories` + DB | `authoritative`; **LFS objects → R2** (S3 backend), not restic |
| OCI registry (zot) | manifests | `authoritative`; **blobs → R2**, not restic |
| `/home` | user data | `authoritative` (already backed up) |

## Why these service choices

- **Forgejo LFS → R2.** Forgejo's `[lfs] STORAGE_TYPE = minio` speaks S3 against
  R2 directly, keeping bulk LFS objects out of restic; repos + the DB (on the
  shared postgres) are the `authoritative` restic targets.
- **Registry = zot.** OCI-native, runs as a plain systemd service (no Docker
  daemon), with a built-in S3/R2 blob backend and GC. Manifests are tiny and
  `authoritative`; blobs live on R2.
- **nativelink / atticd CAS are never restic'd.** Their content is either already
  in R2 or re-derivable; backing it up would pay R2 twice for re-creatable data.
