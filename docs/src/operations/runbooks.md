# Runbooks

Copy-pasteable procedures for the stateful infra. These are the one-time / recovery steps that
aren't expressed declaratively — everything else is in the modules. See
[Deploying a host](./deploying.md) for the rebuild commands these reference.

---

## A — Stand up the central attic cache on watchtower

`watchtower` runs the `monolithic-shared` attic profile: the single shared PostgreSQL + the
monolithic `atticd` (the only node that migrates and runs GC), backed by R2. Most of this is
declarative — these are the **one-time bootstrap** steps. See
[Binary cache (attic)](../infrastructure/attic.md).

Prereqs: the `atticd-rs256.age` secret exists and is rekeyed to `watchtower` (carries
`ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64`, `PGPASSWORD`, and the R2 `AWS_*` creds). The
`hyper-modern-nixos.attic-node` block is enabled (its own `enable = true`) in
`configurations/nixos/watchtower/configuration.nix` — modules self-wire their secrets, so staging is
just uncommenting that block and rebuilding.

1. **Deploy the infra.** On switch the declarative chain runs automatically:
   - postgres comes up; `ensureDatabases`/`ensureUsers` create the `atticd` role
     - db (`ensureDBOwnership`);
   - the `postgresql-role-passwords` oneshot sets the `atticd` role password from the agenix secret
     (`PGPASSWORD`), so md5 login matches the client;
   - `atticd` (monolithic) connects over loopback, **runs migrations**, serves.

   ```bash
   nixos-rebuild switch --flake .#watchtower \
     --target-host watchtower --use-remote-sudo
   ssh watchtower systemctl status postgresql atticd
   ```

2. **Mint an admin token** (RS256 signing secret is already loaded into atticd):

   ```bash
   ssh watchtower 'atticd-atticadm make-token \
     --sub bootstrap --validity 1h \
     --pull "*" --push "*" --create-cache "*" --configure-cache "*"'
   ```

3. **Create + publish the cache, once**, using that token with the `attic` CLI:

   ```bash
   attic login hypermodern http://watchtower.osiris-walleye.ts.net:8080 <TOKEN>
   attic cache create    hypermodern
   attic cache configure hypermodern --public      # anonymous pull
   attic cache info       hypermodern              # prints the public key
   ```

   The public key must match the fleet-wide `hyper-modern-nixos.attic-node.publicKey`
   (`hypermodern:x+kBunu5nD1KOhzCIawyZeq8w0LV0GC6A7suIRoHTm8=`). After the row exists, the
   `attic-cache-keypair-restore` oneshot (runbook D) keeps its signing key stable.

4. Other hosts use `profile = "replica"` and pull/push automatically via `watch-store`.

---

## B — restic first backup by hand

The backup module sets `initialize = false` **by design**: you create and verify the repo by hand
before any timer touches your data. See [Backups (restic → R2)](../infrastructure/backups.md). On
`watchtower` the secrets are `restic-password` (repo passphrase) and `restic-r2-env.watchtower`
(`RESTIC_REPOSITORY` + R2 `AWS_*`), both self-wired by the `hyper-modern-nixos.backup` module's own
`enable`.

Deploy with the `hyper-modern-nixos.backup` block enabled (so the secrets decrypt) — `initialize =
false` means the timer can't create or touch the repo until you've done it by hand — then on the
host:

1. **Init the repo:**

   ```bash
   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
     env $(sudo cat /run/agenix/restic-r2-env.watchtower | xargs) \
     restic init
   ```

2. **First backup + verify:**

   ```bash
   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
     env $(sudo cat /run/agenix/restic-r2-env.watchtower | xargs) \
     restic backup /home

   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
     env $(sudo cat /run/agenix/restic-r2-env.watchtower | xargs) \
     restic snapshots
   ```

3. **Then let the timer take over.** With the `hyper-modern-nixos.backup` block enabled in
   `configurations/nixos/watchtower/configuration.nix` (uncomment it if it was staged out) and
   rebuilt, the systemd unit (`restic-backups-system.service`) takes over the same repo with the
   same password + env file, plus retention (`pruneOpts`) and a post-backup
   `restic check --read-data-subset=10%`.

> **Losing `restic-password` = unrecoverable backups.** Keep an out-of-band copy.

---

## C — PostgreSQL collation-version mismatch after a glibc bump

A NixOS upgrade can bump glibc and change ICU/libc collation versions, after which postgres warns
`database "<db>" has a collation version mismatch`. Refresh the recorded version on the affected
databases **and `template1`**:

```bash
ssh watchtower
sudo -u postgres psql -c 'ALTER DATABASE atticd    REFRESH COLLATION VERSION;'
sudo -u postgres psql -c 'ALTER DATABASE postgres  REFRESH COLLATION VERSION;'
sudo -u postgres psql -c 'ALTER DATABASE template1 REFRESH COLLATION VERSION;'
```

Refreshing `template1` ensures freshly-created databases inherit the correct version. If you suspect
text indexes were built under the old collation, `REINDEX DATABASE atticd;` afterwards.

---

## D — Cache signing keypair recovery

attic stores the cache's signing keypair **only** in the postgres `cache` table and has no import
CLI — a postgres wipe would regenerate it and break every client's trusted public key. We persist it
in agenix (`attic-cache-keypair.age`) and restore it on activation.

This is **automatic** on the `monolithic-shared` node: the `attic-cache-keypair-restore` oneshot
(`modules/nixos/attic-node.nix`) runs after `postgresql-role-passwords` and before `atticd`, and
`UPDATE`s the keypair on the existing `cache` row from the agenix secret. To force it after a
postgres restore:

```bash
ssh watchtower
# ensure the cache row exists first (runbook A step 3), then:
sudo systemctl restart attic-cache-keypair-restore.service
sudo systemctl restart atticd.service
attic cache info hypermodern    # public key must equal the fleet's publicKey
```

The restore only **updates an existing row** — the row itself is created once at bootstrap by
`attic cache create` (runbook A).

---

## E — Rekey all secrets after adding/rotating a host key

After editing `secrets/keys.nix` (added or rotated a host/user key), re-encrypt every `.age` file to
the new recipient set:

```bash
nix run .#rekey-secrets        # runs `agenix -r` from secrets/
```

A host can only decrypt a secret once its key is in `keys.nix` **and** the secret has been rekeyed
to include it. See [Adding a host](./adding-a-host.md#3-scan--add-the-host-key-then-rekey-secrets)
and [Secrets (agenix)](../infrastructure/secrets.md).
