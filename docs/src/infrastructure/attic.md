# Binary cache (attic)

The fleet runs [attic](https://github.com/zhaofengli/attic) (`atticd`) as a
shared, R2-backed Nix binary cache named **`hypermodern`**. Built from
`modules/nixos/attic.nix` (the low-level option surface) and
`modules/nixos/attic-node.nix` (a profile selector). **Off by default.**

Cache public key:

```
hypermodern:x+kBunu5nD1KOhzCIawyZeq8w0LV0GC6A7suIRoHTm8=
```

## Topology: replicated api-server + shared state

Per the attic docs, `atticd` splits cleanly:

- **api-server** — STATELESS, can be replicated. We run one per host.
- **garbage-collector** — CANNOT be replicated. **Exactly one** node runs it.
- **monolithic** — runs everything (api-server + the GC); single instance.

All durable state lives **outside** `atticd`:

- **postgres** (on [`watchtower`](./postgres.md)) holds cache metadata.
- an **R2 bucket** (`straylight-attic-cache`) holds the content-addressed
  NAR/chunk store. Dedup is **global** — every host's local api-server
  reads/writes the same logical cache.

```
                      ┌──────────────────────────────────────────┐
                      │  shared state (the single source of truth)│
                      │                                            │
   ┌──────────┐  pg   │   postgres (watchtower)   R2 chunk store   │
   │ replica  │──────▶│        (metadata)        (content-addr,    │
   │ api-srv  │  R2   │                           global dedup)    │
   └────┬─────┘──────▶└──────────────────────────────────────────┘
        │ localhost:8080                       ▲   ▲
   substituters first                          │   │
                                          ┌────┴───┴────┐
                                          │ monolithic- │  api-server + the
                                          │   shared    │  ONE gc + migrations
                                          │ (watchtower)│
                                          └─────────────┘
```

Each host points its Nix **substituters at its OWN `localhost:8080` first**, so
there's no serialization through one box — but the truth is shared. The RS256
JWT signing secret is **identical on every node** so tokens verify fleet-wide.

## The `attic-node` profile selector

`hyper-modern-nixos.attic-node` is a profile over the orthogonal axes
(mode × database × storage), so any host switches cleanly **regardless of fleet
state**. The cache identity (name, public key, push token) is constant, so a
host flips between profiles by changing one enum with no other churn.

| Profile | Mode | Database | Storage | Fleet dependency |
|---|---|---|---|---|
| `standalone` | monolithic | local sqlite (or local pg via `standalonePostgres`) | local fs (or R2 via `r2.enable`) | **none** — activates anywhere, today |
| `replica` | api-server | shared pg over the tailnet | R2 | needs shared pg **up + already migrated** |
| `monolithic-shared` | monolithic | local pg (it **is** the pg host) | R2 | watchtower's role: pg + the single GC + migrations |

`standalone` is the profile to run before watchtower's shared postgres exists,
or for any island cache. `replica` requires the shared backend up — a bare
api-server does not run migrations. **Exactly one** node uses
`monolithic-shared`.

```nix
# configurations/nixos/watchtower/configuration.nix  (the central backend)
age.secrets.atticd-rs256.file        = …/atticd-rs256.age;
age.secrets.attic-push-token.file    = …/attic-push-token.age;
age.secrets.attic-cache-keypair.file = …/attic-cache-keypair.age;
hyper-modern-nixos.attic-node = { enable = true; profile = "monolithic-shared"; };

# configurations/nixos/ultraviolence/configuration.nix  (a stateless replica)
age.secrets.atticd-rs256.file     = …/atticd-rs256.age;
age.secrets.attic-push-token.file = …/attic-push-token.age;
hyper-modern-nixos.attic-node = { enable = true; profile = "replica"; };
```

Every profile also enables the client side: substituters → `localhost:8080`
first, trusts the public key, and runs `attic watch-store` for auto-push.

## Passwordless `databaseUrl` + `PGPASSWORD`

The postgres connection string set in the config file is **passwordless** and
non-secret:

```
postgresql://atticd@watchtower.osiris-walleye.ts.net/atticd
```

attic uses `sea-orm` + `sqlx-postgres`, and `sqlx` honors libpq env vars — so
the password is supplied **separately** via `PGPASSWORD` inside the agenix env
file and **never enters the Nix store**. A password in the URL would leak into
the store via the rendered config; the module `mkForce`s the passwordless URL
and lets `PGPASSWORD` do the auth.

The `monolithic-shared` profile (watchtower) maps the URL to `localhost` since
it *is* the pg host; `replica` uses the remote tailnet URL. It also sets the
`atticd` role password declaratively from the **same** agenix secret atticd
reads `PGPASSWORD` from (via [postgres `rolePasswords`](./postgres.md)), so the
md5 login and client password can't drift.

## The env file (`atticd-rs256`)

One agenix secret, [`atticd-rs256`](./secrets.md), carries everything that may
**not** touch the store, as single-line env vars (systemd `EnvironmentFile`
can't parse a multi-line PEM):

```
ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<base64 -w0 of an RSA PKCS1 PEM>
PGPASSWORD=<postgres password for the atticd role>      # sqlx reads it
AWS_ACCESS_KEY_ID=…                                      # R2 chunk-store creds
AWS_SECRET_ACCESS_KEY=…
```

Generate the RS256 secret once and store it fleet-wide (it MUST be identical on
every node):

```sh
echo "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(openssl genrsa -traditional 4096 | base64 -w0)"
```

The push token ([`attic-push-token`](./secrets.md)) is a raw JWT minted with:

```sh
atticd-atticadm make-token --sub <host>-push --validity 10y \
  --pull hypermodern --push hypermodern
```

## Cache signing keypair persistence

This is the subtle part. attic stores the cache's signing keypair **only** in
the postgres `cache` table and has **no import CLI**. So a postgres wipe
regenerates the key, and every client's trusted public key breaks.

To make the signing identity **stable and recoverable regardless of postgres
state**, we persist the `NixKeypair` string in agenix
([`attic-cache-keypair`](./secrets.md)) and restore it into the `cache` row on
activation:

- The secret is granted `group = "postgres"`, `mode = "0440"` (postgres-readable).
- A `oneshot` (`attic-cache-keypair-restore`) runs after
  `postgresql-role-passwords.service` and **before** `atticd.service`, as the
  `postgres` user, and idempotently:

  ```sql
  UPDATE cache SET keypair = '<agenix value>' WHERE name = 'hypermodern';
  ```

It only **updates an existing** row (the row is created at bootstrap by
`attic cache create`), keeping the signing key stable thereafter. Only the
`monolithic-shared` node does this. Set `keypairSecret = null` to disable
restore and use the DB-generated key (which changes on a wipe).

> `atticd` is also ordered `after`/`wants` the role-password oneshot, so it
> never races md5 auth and crash-loops before the password is set.

## Client side & `watch-store` auto-push

`hyper-modern-nixos.attic.clientCache` (set automatically by every
`attic-node` profile) wires the cache as a substituter, trusts its key, and
runs auto-push:

- **Substituter, consulted first**: prepended with `mkBefore` and given
  `?priority=10`, so Nix tries `hypermodern` before `cache.nixos.org` (40).
- **`attic watch-store`**: the canonical daemon (`atticd-watch-store.service`)
  watches the store and uploads **new** paths continuously — strictly better
  than a post-build-hook (catches built **and** substituted/copied-in paths,
  runs async, no `OUT_PATHS` plumbing). Only started when a push token is
  provided (else pull-only).
- Auth via a generated client config (`XDG_CONFIG_HOME`) whose only secret is a
  `token-file` reference to the agenix path — the JWT never enters the store.
- Ordered after `tailscaled.service` so the cache's MagicDNS endpoint resolves
  (otherwise it races DNS at boot and crash-loops on NXDOMAIN).

Hosts that don't run `atticd` can still be pure clients via
`hyper-modern-nixos.attic.clientCache` pointing at a server over the tailnet.

## Firewall

`atticd` binds `[::]:8080` but the port is opened **only** on `trustedInterfaces`
(`tailscale0`), so the cache is tailnet-reachable, never internet-exposed.
