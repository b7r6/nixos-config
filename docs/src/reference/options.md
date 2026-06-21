# Module options

Reference for the `hyper-modern-nixos.*` options exposed by the NixOS infra modules under
`modules/nixos/`. The authoritative source is the module that declares each option (linked per
section) — option descriptions and defaults live there. This page summarizes the **infra-relevant**
options.

## `network.tailscale.*` / `network.firewall.*`

Source: `modules/nixos/network.nix`. The `network` module is enabled by default
(`hyper-modern-nixos.network.enable = true`).

| Option | Type / default | Description | | ------------------------------------------------- |
------------------------------------------- |
--------------------------------------------------------------------------- | |
`network.tailscale.authKeyFile` | `null or path` / `null` | Auth-key file for **declarative**
enrollment (an agenix runtime path). When set, `tailscaled` enrolls non-interactively — a rebuild
can't strand a remote box. | | `network.tailscale.acceptRoutes` | `bool` / `true` | Accept subnet
routes advertised by other nodes. | | `network.tailscale.acceptDNS` | `bool` / `true` | Accept
MagicDNS / tailnet DNS. | | `network.tailscale.advertiseRoutes` | `listOf str` / `[ ]` | Subnets
this node advertises (subnet router). | | `network.tailscale.advertiseExitNode` | `bool` / `false` |
Advertise this node as an exit node. | | `network.tailscale.acceptExitNode` | `bool` / `false` |
Allow LAN access while using an exit node. | | `network.tailscale.advertiseConnector` | `bool` /
`false` | Advertise as a Tailscale app connector. | | `network.tailscale.sshAdvertise` | `bool` /
`true` | Advertise Tailscale SSH. | | `network.tailscale.tags` | `listOf str` / `[ ]` | Tags to
advertise (must be authorized by the tailnet ACL). | | `network.tailscale.hostname` | `null or str`
/ `null` | Override the registered Tailscale hostname. | | `network.tailscale.encryptState` | `bool`
/ `false` | Encrypt `tailscaled` state via TPM 2.0. Off — boxes are reflashed often. | |
`network.firewall.enable` | `bool` / `true` | Tailscale-aware firewall. The fleet runs firewall-off;
the DB host opts back in so interface-scoped rules bite. | | `network.tailnet.domain` | `str` /
`"example.ts.net"` | Tailnet domain. | | `network.useBackupResolver` | `bool` / `false` | Use backup
DNS resolvers in addition to Tailscale DNS. |

See [Tailscale](../infrastructure/tailscale.md).

## `databases.postgres.*`

Source: `modules/nixos/postgres.nix`. **Off by default** — the fleet runs exactly one shared
postgres (on `watchtower`).

| Option | Type / default | Description | | -------------------------------------------- |
--------------------------------------------------------- |
--------------------------------------------------------------------------- | |
`databases.postgres.enable` | `bool` / `false` | Enable the PostgreSQL server. | |
`databases.postgres.package` | package / `postgresql_16` | Server package. | |
`databases.postgres.tailnet.enable` | `bool` / `false` | Listen on the tailnet + permit md5 auth
from the tailnet CIDRs. | | `databases.postgres.tailnet.interface` | `str` / `"tailscale0"` |
Interface whose address postgres additionally binds (firewall scope). | |
`databases.postgres.tailnet.cidrs` | `listOf str` / `[100.64.0.0/10, fd7a:115c:a1e0::/48]` | Source
CIDRs permitted (md5) in `pg_hba` for tailnet access. | | `databases.postgres.ensureDatabases` |
`listOf str` / `[ ]` | Databases to create declaratively. | | `databases.postgres.ensureUsers` |
`listOf attrs` / `[ ]` | Roles to create declaratively (peer-auth only; no store password). | |
`databases.postgres.settings` | `attrs` / `{ }` | Extra `services.postgresql.settings`. | |
`databases.postgres.rolePasswords.<role>.secret` | `str` | agenix secret **name** to source the role
password from (runtime, never the store). | | `databases.postgres.rolePasswords.<role>.var` | `str`
/ `"PGPASSWORD"` | Env var within the secret holding the password. | | `databases.redis.enable` |
`bool` / `false` | Enable Redis. |

See [PostgreSQL](../infrastructure/postgres.md).

## `attic-node.*` (the profile selector)

Source: `modules/nixos/attic-node.nix`. The high-level "be a cache node" knob — selects a profile
over the orthogonal `attic` axes (mode × database × storage). A host sets just this plus the
`atticd-rs256` / `attic-push-token` secrets.

| Option | Type / default | Description | | ----------------------------------- |
------------------------------------------------------------------------------- |
--------------------------------------------------------------------------- | | `attic-node.enable`
| `bool` / `false` | Be an attic cache node. | | `attic-node.profile` | enum `standalone` |
`replica` | `monolithic-shared` / `"standalone"` | `standalone`: self-contained. `replica`:
api-server against the shared pg + R2. `monolithic-shared`: the one node that migrates + runs GC. |
| `attic-node.environmentFile` | `str` / `"/run/agenix/atticd-rs256"` | Env file: RS256 secret (+ R2
`AWS_*`, + `PGPASSWORD` for shared profiles). | | `attic-node.pushTokenFile` | `null or str` /
`"/run/agenix/attic-push-token"` | Push JWT for `watch-store`. `null` = pull-only. | |
`attic-node.sharedDatabaseUrl` | `str` /
`postgresql://atticd@watchtower.osiris-walleye.ts.net/atticd` | Passwordless shared-pg URL for
`replica` (PGPASSWORD via env file). | | `attic-node.standalonePostgres` | `bool` / `false` |
`standalone` only: use a local postgres instead of sqlite. | | `attic-node.r2.enable` | `bool` /
`false` | Back storage with R2 (forced on for shared profiles). | | `attic-node.r2.bucket` | `str` /
`"straylight-attic-cache"` | R2 chunk-store bucket. | | `attic-node.r2.endpoint` | `str` / R2 S3
endpoint | R2 S3 endpoint. | | `attic-node.publicKey` | `str` /
`hypermodern:x+kBunu5nD1KOhzCIawyZeq8w0LV0GC6A7suIRoHTm8=` | The `hypermodern` cache binary-cache
public key. | | `attic-node.cacheName` | `str` / `"hypermodern"` | Cache name (URL path segment + DB
cache row). | | `attic-node.keypairSecret` | `null or str` / `"attic-cache-keypair"` |
`monolithic-shared` only: agenix secret holding the NixKeypair, restored into the `cache` row on
activation. |

## `attic.*` (the low-level atticd module)

Source: `modules/nixos/attic.nix`. Driven by `attic-node` in normal use; set directly only for
bespoke topologies. **Off by default.**

| Option | Type / default | Description | | ------------------------------------- |
----------------------------------------------- |
------------------------------------------------------------------------ | | `attic.enable` | `bool`
/ `false` | Run `atticd`. | | `attic.mode` | enum `monolithic` | `api-server` | `garbage-collector`
/ `"monolithic"` | atticd run mode. Only one node may run GC. | | `attic.databaseUrl` |
`null or str` / `null` | **Passwordless** postgres URL (PGPASSWORD via env file). `null` = sqlite. |
| `attic.environmentFile` | `null or path` / `null` | Env file with
`ATTIC_SERVER_TOKEN_RS256_SECRET*` (required when enabled). | | `attic.listen` | `str` /
`"[::]:8080"` | Bind address (port opened only on `trustedInterfaces`). | |
`attic.trustedInterfaces` | `listOf str` / `[ "tailscale0" ]` | Interfaces the port is opened on. |
| `attic.openFirewall` | `bool` / `true` | Open the listen port (on `trustedInterfaces` only). | |
`attic.storage.type` | enum `local` | `s3` / `"local"` | Storage backend. | | `attic.storage.path` |
`str` / `"/var/lib/atticd/storage"` | Local storage dir (`type = local`). | | `attic.storage.region`
| `str` / `"auto"` | S3 region (R2 = `auto`). | | `attic.storage.bucket` | `str` / `""` | S3 bucket
(`type = s3`). | | `attic.storage.endpoint` | `str` / `""` | Custom S3 endpoint (R2/Minio). | |
`attic.settings` | `attrs` / `{ }` | Extra `services.atticd.settings` (TOML). | |
`attic.clientCache.enable` | `bool` / `false` | Use a cache as substituter + `watch-store`
auto-push. | | `attic.clientCache.name` | `str` / `"hypermodern"` | Cache name (URL path segment). |
| `attic.clientCache.endpoint` | `str` | Base atticd URL (no trailing slash, no cache name). | |
`attic.clientCache.publicKey` | `str` | Cache binary-cache public key. | |
`attic.clientCache.priority` | `int` / `10` | Substituter priority (lower = tried first; beats
`cache.nixos.org`). | | `attic.clientCache.pushTokenFile` | `null or path` / `null` | Push JWT file.
`null` = pull-only (no `watch-store`). |

See [Binary cache (attic)](../infrastructure/attic.md).

## `backup.*`

Source: `modules/nixos/backup.nix`. restic backups, **off by default** — do the first run by hand
(`initialize = false`). See [Backups (restic → R2)](../infrastructure/backups.md) and the
[restic runbook](../operations/runbooks.md#b--restic-first-backup-by-hand).

| Option | Type / default | Description | | ---------------------------- |
--------------------------------------------------------------- |
------------------------------------------------------------------------ | | `backup.enable` |
`bool` / `false` | Enable the restic timer. | | `backup.repository` | `str` / `""` | Repo location.
Leave empty when `RESTIC_REPOSITORY` is in the env file. | | `backup.passwordFile` | `path` /
`"/run/agenix/restic-password"` | Repo passphrase file (agenix runtime path; never the store). | |
`backup.environmentFile` | `null or path` / `null` | Env file with backend creds (+
`RESTIC_REPOSITORY` for the S3/R2 path). | | `backup.paths` | `listOf str` /
`[ /home /etc /var/lib ]` | Paths to back up. | | `backup.exclude` | `listOf str` / large default |
Glob excludes — caches, re-fetchable ML weights, build scratch. | | `backup.timerConfig` | `attrs` /
`{ OnCalendar = "daily"; Persistent; RandomizedDelaySec = "1h"; }` | systemd timer config. | |
`backup.pruneOpts` | `listOf str` / `--keep-daily 7` … `--keep-yearly 3` | Retention policy
(`restic forget`). |

## Other infra options

- `hyper-modern-nixos.users.*` — fleet-wide user model (groups, authorized keys, admin flag).
  Source: `modules/nixos/myusers.nix`.
- `hyper-modern-nixos.secrets.enable` — 1Password + Yubikey/PAM packages. Source:
  `modules/nixos/secrets.nix`.

> This table is not exhaustive across every home-manager module. For the authoritative type,
> default, and prose for any option, read the `mkOption` / `mkEnableOption` declaration in the
> module named at the top of each section.
