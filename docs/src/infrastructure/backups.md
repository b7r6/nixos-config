# Backups (restic → R2)

restic backups to **Cloudflare R2**, from `modules/nixos/backup.nix` under
`hyper-modern-nixos.backup`. **Off by default**, and refuses to do anything until a host opts in —
so it cannot brick a box.

> Philosophy: **the first backup is done by hand.** You init the repo, run one full backup, and
> verify a restore manually *before* any systemd timer touches your data. Once you trust it, flip
> `enable = true` and the timer takes over the exact same repo with the exact same settings. See
> also [`BACKUP.md`](../../../BACKUP.md) in the repo root.

## Per-host repo layout

One R2 bucket, **one repo per machine** under a per-host prefix (`<bucket>/<host>`), so each
host gets an isolated repo — own locks, own retention — while sharing the same bucket and R2 token.
The bucket name isn't pinned in code; it lives only in the encrypted env file as part of
`RESTIC_REPOSITORY`.

The repo URL and backend creds live in a **per-host agenix env file**
([`restic-r2-env.<host>`](./secrets.md)), keeping the account id out of the Nix store:

```
RESTIC_REPOSITORY=s3:https://<acct>.r2.cloudflarestorage.com/<bucket>/<host>
AWS_ACCESS_KEY_ID=…
AWS_SECRET_ACCESS_KEY=…
AWS_DEFAULT_REGION=auto
```

The repo password is the separate [`restic-password`](./secrets.md) secret (shared fleet-wide).
**Losing this = unrecoverable backups** — keep an out-of-band copy.

```nix
# configurations/nixos/watchtower/configuration.nix
hyper-modern-nixos.backup = {
  enable = true;
  passwordSecret    = "restic-password";          # module self-wires age.secrets
  environmentSecret = "restic-r2-env.watchtower";  # PER-HOST; carries RESTIC_REPOSITORY
  paths = [ "/home" ];                             # widen to /etc /var/lib once trusted
};
```

A host only names its secrets — the module declares `age.secrets.<name>.file` from the
repo and derives the runtime path itself (`environmentSecret = "restic-r2-env.watchtower"`
→ `environmentFile = "/run/agenix/restic-r2-env.watchtower"`), so there is no parallel
hand-written `age.secrets` entry to keep in sync.

When the env file provides `RESTIC_REPOSITORY`, leave `.repository` empty — the module passes
`repository = null` so restic's upstream "exactly one source" assertion passes and the env file is
the sole source of the location.

## Exclude list

The defaults exclude everything re-downloadable, so R2 only ever holds irreplaceable data:

- **Caches** — `~/.cache`, `~/.local/state/nix`, `~/.local/share/{uv,pnpm,virtualenvs}`, `~/.npm`,
  `~/.cargo/registry`, `~/.rustup`, `~/.ollama/models`, Trash.
- **ML/model weights, by extension** (blanket — disposable everywhere on these boxes):
  `*.safetensors`, `*.ckpt`, `*.gguf`, `*.pt`, `*.pth`, `*.onnx`, `*.h5`, `*.pb`, plus `~/models`
  and `~/.cache/huggingface`.
- **Build/VCS scratch** — `/var/lib/{docker,containers}`, `**/node_modules`, `**/.direnv`,
  `**/result{,-bin}`, `**/target`, `**/__pycache__`, `**/.venv`, `**/.mypy_cache`, `**/.ruff_cache`,
  `**/.pytest_cache`.

> If a future host does **real** training, override `exclude` there to keep its run outputs (the
> weight exclusions are deliberately blanket).

## Schedule, retention, integrity

| Setting | Default |
| --- | --- |
| `timerConfig` | `OnCalendar=daily`, `Persistent=true`, `RandomizedDelaySec=1h` |
| `pruneOpts` | `--keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 3` |
| `checkOpts` | `--read-data-subset=10%` (runs after each backup) |
| `initialize` | `false` — the repo **must** exist already |

The timer (`restic-backups-system.timer`) runs the backup, prunes to the retention policy, then runs
a partial integrity check so a slowly-corrupting repo is caught by the timer rather than at restore
time. `initialize = false` is deliberate: a misconfiguration can never silently create a brand-new
empty repo and "succeed".

## First run (by hand) — runbook

The very first backup is **manual**, before any timer is enabled:

```sh
# decrypted secrets must be present on the host
sudo test -r /run/agenix/restic-password
sudo test -r /run/agenix/restic-r2-env.watchtower

export RESTIC_PASSWORD_FILE=/run/agenix/restic-password

# 1. init the repo (RESTIC_REPOSITORY + R2 creds come from the env file)
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env.watchtower | xargs) restic init

# 2. one full backup (env file in scope)
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env.watchtower | xargs) restic backup /home

# 3. VERIFY — snapshots, integrity, trial restore
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env.watchtower | xargs) restic snapshots
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env.watchtower | xargs) restic check --read-data-subset=10%
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env.watchtower | xargs) \
  restic restore latest --target /tmp/restore-test --include /etc/hostname
```

Only if all three look right: set `hyper-modern-nixos.backup.enable = true` and rebuild. The timer
then operates the **same** repo.

> A local-repo variant of the runbook (no R2) is in [`BACKUP.md`](../../../BACKUP.md).

## Operating

```sh
systemctl status  restic-backups-system.service
systemctl start   restic-backups-system.service     # run now
journalctl -u     restic-backups-system.service -e
```

# PostgreSQL backups

Two independent layers, both from `modules/nixos/postgres.nix` under
`hyper-modern-nixos.databases.postgres.backup`. See the
[state & backup model](../architecture/state-and-backup.md) for why postgres is
backed up via **dumps/WAL**, never by restic-ing the live cluster dir.

## Layer 1 — logical dumps (RPO ~24h, cross-version)

`backup.enable` (on whenever postgres is enabled) runs a timer that does
`pg_dumpall --clean --if-exists | zstd` into `backup.dumpDir`
(`/var/backup/postgres`). That dir is classified **`authoritative`** state, so
restic ships it to R2 with everything else. Logical dumps restore **across PG
majors** — the portable floor, and the belt to PITR's suspenders.

| Setting | Default |
| --- | --- |
| `backup.onCalendar` | `daily` |
| `backup.keep` | `7` local dumps (restic holds the longer history) |
| `backup.dumpDir` | `/var/backup/postgres` (authoritative → restic'd) |

```sh
systemctl start postgres-dump.service        # dump now
ls -la /var/backup/postgres/                  # pg_dumpall-<ts>.sql.zst
```

## Layer 2 — PITR via pgBackRest (RPO ~seconds, single node)

`backup.pitr.enable` turns on continuous **WAL archiving + base backups** to a
**dedicated R2 bucket** (`straylight-pg-pitr`), dropping the recovery point from
~24h to ~seconds **on a single machine** — a full wipe loses almost nothing. This
is the durability the system-of-record (e.g. Forgejo) needs.

It is **not** streaming replication: there is no second postgres and no failover.
PITR is single-node *recoverability*; HA is a separate, later project.

> **Proven live on watchtower** (2026-06): stanza `main` status ok; WAL archives
> continuously to R2; a full base backup (187 MB → 49 MB compressed) and a
> **restore rehearsal** (full cluster reconstructed from R2 to a scratch dir,
> 1318 files, valid PG 16) both completed. PITR is trusted, not a rumor.

How it wires up:

- postgres gets `archive_mode = on`, `wal_level = replica`, and
  `archive_command = pgbackrest --stanza=<s> archive-push %p` — every completed
  WAL segment is pushed to R2 (and `archive_timeout = 60` forces a segment at
  least once a minute, bounding RPO even when idle).
- A weekly **full** + daily **differential** base backup (`pgbackrest-backup-full`
  / `-diff` timers) anchor the WAL chain and bound restore time.
- The R2 secrets arrive as `PGBACKREST_*` env vars from the agenix
  [`pgbackrest-r2-env`](./secrets.md) file (never the Nix store), fed into
  `postgresql.service` so the `archive_command` subprocess inherits them.
- `pgbackrest-stanza-create.service` does the one-time, idempotent stanza setup
  on activation (like restic-init).

```nix
hyper-modern-nixos.databases.postgres.backup.pitr = {
  enable = true;                       # archive_mode + WAL push + base-backup timers
  # dedicated bucket + R2 endpoint default to straylight-pg-pitr; override if needed
};
```

### Bringup (once, by hand)

```sh
# 1. R2: create a DEDICATED bucket `straylight-pg-pitr` (separate from the restic
#    `backups-restic` bucket, which is preserved untouched). The credentials may
#    reuse the existing account-wide R2 token — the bucket boundary keeps rclone
#    tooling from touching the PITR repo by accident. (A future hardening is a
#    token scoped to ONLY this bucket, for credential blast-radius isolation.)
# 2. agenix: store the creds (PGBACKREST_* env), rekeyed to all hosts:
nix run .#new-secret -- agenix/machines/pgbackrest-r2-env.age
#   PGBACKREST_REPO1_S3_KEY=<r2 access key id>
#   PGBACKREST_REPO1_S3_KEY_SECRET=<r2 secret access key>
# 3. flip pitr.enable on the postgres host, deploy. Activation runs stanza-create.
# 4. verify the stanza + take a first full backup BY HAND before trusting it:
sudo -u postgres pgbackrest --stanza=main check
sudo -u postgres pgbackrest --stanza=main --type=full backup
sudo -u postgres pgbackrest --stanza=main info
```

### Restore runbook (PITR is only trusted once this is tested)

A backup you have never restored is a rumor. Rehearse on a throwaway target
*before* relying on PITR:

```sh
# Restore the whole cluster to a scratch dir (does NOT touch the live cluster):
sudo -u postgres pgbackrest --stanza=main \
  --pg1-path=/var/lib/postgresql/restore-test restore

# Point-in-time: restore to a specific instant (everything up to that LSN/time):
sudo -u postgres pgbackrest --stanza=main \
  --pg1-path=/var/lib/postgresql/restore-test \
  --type=time --target="2026-06-21 18:00:00+00" restore
```

A real recovery is: stop postgres, move the damaged cluster aside, `restore` into
`dataDir`, start postgres (it replays WAL to the target). Write the host-specific
version of that into a per-incident runbook the first time you do it for real.
