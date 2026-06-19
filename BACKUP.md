```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                                                    // hypermodern // backups
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

# `// why`

restic backups, driven by `modules/nixos/common/backup.nix` (`hyper-modern-nixos.backup`). The
module is **off by default** and refuses to do anything until a host opts in.

The rule: **the first backup is done by hand.** You initialize the repo, run one full backup, and
verify a restore — all manually — *before* any systemd timer is allowed near your data. Once you
trust the repo and the retention policy, you flip `enable = true` and the timer takes over the exact
same repo with the exact same password. No surprises.

# `// secrets`

The restic repository password lives in agenix, never in the nix store.

```sh
# from the repo, in the secrets devshell (nix develop .#secrets):
#   create the password secret (encrypts to b7r6 + all configured hosts)
agenix -e secrets/agenix/machines/restic-password.age
#   put a single strong line in it, e.g.:
#     a-long-random-passphrase-you-keep-in-1password
```

It is already declared in `secrets/secrets.nix` as `agenix/machines/restic-password.age`. For cloud
backends (S3/B2/…), create a second env-file secret with the backend credentials and point
`hyper-modern-nixos.backup.environmentFile` at it.

# `// first run (by hand)`

Pick a repository. Local example:

```sh
# 0. make sure the password secret is decrypted on the host.
#    (a host enabling backups declares age.secrets.restic-password +
#     imports the agenix nixos module; the decrypted file lands at
#     /run/agenix/restic-password)
sudo test -r /run/agenix/restic-password

REPO=/srv/backup/restic            # or s3:… / b2:… / rest:…
export RESTIC_PASSWORD_FILE=/run/agenix/restic-password

# 1. initialize the repository
sudo -E restic -r "$REPO" init

# 2. one full backup, matching what the module will back up
sudo -E restic -r "$REPO" backup /home /etc /var/lib \
  --exclude '/home/*/.cache' \
  --exclude '/var/lib/docker' \
  --exclude '**/node_modules' \
  --exclude '**/.direnv'

# 3. VERIFY — list snapshots, check integrity, do a trial restore
sudo -E restic -r "$REPO" snapshots
sudo -E restic -r "$REPO" check --read-data-subset=10%
sudo -E restic -r "$REPO" restore latest --target /tmp/restore-test --include /etc/hostname
cat /tmp/restore-test/etc/hostname   # sanity
```

If — and only if — all three steps look right, enable the service.

# `// enable the timer`

On the chosen host (e.g. in `configurations/nixos/<host>/configuration.nix`):

```nix
# import the agenix module + declare the secret on this host
imports = [ inputs.agenix.nixosModules.default ];
age.secrets.restic-password.file = ../../../secrets/agenix/machines/restic-password.age;

hyper-modern-nixos.backup = {
  enable = true;
  repository = "/srv/backup/restic";        # the SAME repo you inited by hand
  # paths / exclude / pruneOpts / timerConfig have sane defaults; override as needed.
  # environmentFile = config.age.secrets.restic-b2-creds.path;   # for cloud backends
};
```

`nixos-rebuild switch`. The timer (`restic-backups-system.timer`) runs daily with a randomized
delay, prunes to the retention policy, and runs an integrity check after each run.
`initialize = false` is set in the module on purpose: the repo must already exist (you made it in
step 1), so a misconfiguration can never silently create a brand-new empty repo and "succeed".

# `// operating`

```sh
systemctl status  restic-backups-system.service
systemctl start   restic-backups-system.service      # run now
journalctl -u     restic-backups-system.service -e

# inspect / restore (same env as the manual run)
export RESTIC_PASSWORD_FILE=/run/agenix/restic-password
sudo -E restic -r "$REPO" snapshots
sudo -E restic -r "$REPO" restore <snapshot-id> --target /restore --include /home/b7r6/important
```

# `// retention`

Default policy (override via `hyper-modern-nixos.backup.pruneOpts`):

```
--keep-daily 7  --keep-weekly 5  --keep-monthly 12  --keep-yearly 3
```

Pruning happens automatically after each successful backup. A `--read-data-subset=10%` check runs
too, so a slowly-corrupting repo is caught by the timer rather than at restore time.

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                              "Trust, but verify the restore." — not Gibson
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
