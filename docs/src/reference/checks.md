# Checks (NixOS tests)

NixOS VM tests and build checks prove the infra paths end-to-end. They are registered
**per-component** inside each component's `default.nix` — **x86_64-linux only** (a `nixosTest`
needs a Linux builder):

- `modules/flake/attic/default.nix` registers `checks.attic-cache`
- `modules/flake/backup/default.nix` registers `checks.backup-restic`
- `modules/flake/coredns/default.nix` registers `checks.coredns` (VM test)
- `modules/flake/nativelink/default.nix` registers `checks.nativelink` (VM test)
- `modules/flake/default.nix` registers the cross-cutting `checks.state-audit` (build check)

## Running them

```bash
# individually
nix build .#checks.x86_64-linux.attic-cache
nix build .#checks.x86_64-linux.backup-restic
nix build .#checks.x86_64-linux.coredns
nix build .#checks.x86_64-linux.nativelink
nix build .#checks.x86_64-linux.state-audit

# everything the flake checks (incl. these VM tests, fmt, etc.)
nix flake check
```

## `attic-cache`

Source: `checks/attic-cache.nix`. A single VM plays both postgres host and an atticd node,
exercising the **substantive** new code paths behind the central-postgres + replicated api-server
redesign — with **no R2 and no real secrets**:

- `hyper-modern-nixos.databases.postgres` (opt-in, declarative `atticd` role+db);
- `hyper-modern-nixos.attic` in **monolithic** mode with a **passwordless** `databaseUrl`
  (`postgresql://atticd@localhost/atticd`) + `PGPASSWORD` from a build-time env file (a *test*
  secret, in the store on purpose — proving the plumbing, not secrecy);
- `clientCache` → `localhost:8080` as a substituter-first cache.

Storage is **local**, not minio — R2/S3 is just a swappable backend; the wiring under test is mode +
db + substituter, which is backend-agnostic. Monolithic (not bare api-server) is used because only a
monolithic node runs migrations.

What the `testScript` asserts:

1. `postgresql.service` is up and owns the `atticd` database.
2. `atticd.service` becomes active and binds `8080` — proving the passwordless URL + `PGPASSWORD`
   plumbing authenticates (sqlx would fail otherwise).
3. The rendered atticd config uses the postgres URL, **not** the upstream sqlite default, and
   contains no leaked password.
4. `/etc/nix/nix.conf` lists `localhost:8080/hypermodern` + its public key.
5. `GET /hypermodern/nix-cache-info` returns **`401`** (not-yet-public cache), **not `500`** — a
   clean 401 proves migrations ran and the auth layer serves.
6. `atticd-atticadm make-token` mints a token — proving the RS256 signing secret loaded from the env
   file.

## `backup-restic`

Source: `checks/backup-restic.nix`. Proves the restic → S3(R2) backup mechanism is sound, full round
trip. R2 is S3-compatible, so a **local minio stands in for R2** — the code path under test
(`services.restic` via `hyper-modern-nixos.backup` + `RESTIC_REPOSITORY` from the env file +
password file) is identical.

> minio is flagged insecure in nixpkgs; the test permits it **only inside the test VM's node pkgs**
> (`config.permittedInsecurePackages`, `node.pkgs = lib.mkForce …`), never on the fleet. The
> restic→S3 path under test is unaffected by minio's advisory flag.

The `testScript` proves the full round trip:

1. minio (S3) up + bucket created (`mc mb`).
2. Manual `restic init` — the module sets `initialize = false` by design (mirrors the
   [runbook](../operations/runbooks.md#b--restic-first-backup-by-hand)).
3. Seed real data (`important.txt`, `blob.bin`) + an excluded `model.safetensors`, then run the
   generated `restic-backups-system.service`; assert `Result=success`.
4. A snapshot exists (`restic snapshots --json`).
5. **Excludes bite**: `important.txt` + `blob.bin` are in the snapshot, `*.safetensors` is **not**.
6. Repo integrity: `restic check --read-data-subset=100%` (the module runs `--read-data-subset=10%`
   post-backup).
7. **Restore round trip**: restore `latest` to a clean dir and byte-compare (`cmp`); confirm the
   excluded file is absent.

See [Backups (restic → R2)](../infrastructure/backups.md) and
[Binary cache (attic)](../infrastructure/attic.md).
