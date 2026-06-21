# Backups (restic → R2)

restic backups to **Cloudflare R2**, from `modules/nixos/backup.nix` under
`hyper-modern-nixos.backup`. **Off by default**, and refuses to do anything
until a host opts in — so it cannot brick a box.

> Philosophy: **the first backup is done by hand.** You init the repo, run one
> full backup, and verify a restore manually *before* any systemd timer touches
> your data. Once you trust it, flip `enable = true` and the timer takes over
> the exact same repo with the exact same settings. See also
> [`BACKUP.md`](../../../BACKUP.md) in the repo root.

## Per-host repo layout

One R2 bucket, **one repo per machine** under a per-host prefix
(`backups-restic/<host>`), so each host gets an isolated repo — own locks, own
retention — while sharing the same bucket and R2 token.

The repo URL and backend creds live in a **per-host agenix env file**
([`restic-r2-env.<host>`](./secrets.md)), keeping the account id out of the Nix
store:

```
RESTIC_REPOSITORY=s3:https://<acct>.r2.cloudflarestorage.com/<bucket>/<host>
AWS_ACCESS_KEY_ID=…
AWS_SECRET_ACCESS_KEY=…
AWS_DEFAULT_REGION=auto
```

The repo password is the separate [`restic-password`](./secrets.md) secret
(shared fleet-wide). **Losing this = unrecoverable backups** — keep an
out-of-band copy.

```nix
# configurations/nixos/watchtower/configuration.nix
age.secrets.restic-password.file = …/restic-password.age;
age.secrets.restic-r2-env.file   = …/restic-r2-env.watchtower.age;

hyper-modern-nixos.backup = {
  enable = true;
  passwordFile    = "/run/agenix/restic-password";
  environmentFile = "/run/agenix/restic-r2-env";   # carries RESTIC_REPOSITORY
  paths = [ "/home" ];                              # widen to /etc /var/lib once trusted
};
```

When the env file provides `RESTIC_REPOSITORY`, leave `.repository` empty — the
module passes `repository = null` so restic's upstream "exactly one source"
assertion passes and the env file is the sole source of the location.

## Exclude list

The defaults exclude everything re-downloadable, so R2 only ever holds
irreplaceable data:

- **Caches** — `~/.cache`, `~/.local/state/nix`, `~/.local/share/{uv,pnpm,virtualenvs}`,
  `~/.npm`, `~/.cargo/registry`, `~/.rustup`, `~/.ollama/models`, Trash.
- **ML/model weights, by extension** (blanket — disposable everywhere on these
  boxes): `*.safetensors`, `*.ckpt`, `*.gguf`, `*.pt`, `*.pth`, `*.onnx`,
  `*.h5`, `*.pb`, plus `~/models` and `~/.cache/huggingface`.
- **Build/VCS scratch** — `/var/lib/{docker,containers}`, `**/node_modules`,
  `**/.direnv`, `**/result{,-bin}`, `**/target`, `**/__pycache__`, `**/.venv`,
  `**/.mypy_cache`, `**/.ruff_cache`, `**/.pytest_cache`.

> If a future host does **real** training, override `exclude` there to keep its
> run outputs (the weight exclusions are deliberately blanket).

## Schedule, retention, integrity

| Setting | Default |
|---|---|
| `timerConfig` | `OnCalendar=daily`, `Persistent=true`, `RandomizedDelaySec=1h` |
| `pruneOpts` | `--keep-daily 7 --keep-weekly 5 --keep-monthly 12 --keep-yearly 3` |
| `checkOpts` | `--read-data-subset=10%` (runs after each backup) |
| `initialize` | `false` — the repo **must** exist already |

The timer (`restic-backups-system.timer`) runs the backup, prunes to the
retention policy, then runs a partial integrity check so a slowly-corrupting
repo is caught by the timer rather than at restore time. `initialize = false`
is deliberate: a misconfiguration can never silently create a brand-new empty
repo and "succeed".

## First run (by hand) — runbook

The very first backup is **manual**, before any timer is enabled:

```sh
# decrypted secrets must be present on the host
sudo test -r /run/agenix/restic-password
sudo test -r /run/agenix/restic-r2-env

export RESTIC_PASSWORD_FILE=/run/agenix/restic-password

# 1. init the repo (RESTIC_REPOSITORY + R2 creds come from the env file)
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env | xargs) restic init

# 2. one full backup (env file in scope)
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env | xargs) restic backup /home

# 3. VERIFY — snapshots, integrity, trial restore
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env | xargs) restic snapshots
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env | xargs) restic check --read-data-subset=10%
sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  env $(sudo cat /run/agenix/restic-r2-env | xargs) \
  restic restore latest --target /tmp/restore-test --include /etc/hostname
```

Only if all three look right: set `hyper-modern-nixos.backup.enable = true` and
rebuild. The timer then operates the **same** repo.

> A local-repo variant of the runbook (no R2) is in [`BACKUP.md`](../../../BACKUP.md).

## Operating

```sh
systemctl status  restic-backups-system.service
systemctl start   restic-backups-system.service     # run now
journalctl -u     restic-backups-system.service -e
```
