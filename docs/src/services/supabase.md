# Supabase (self-hosted) on `watchtower`

> **Status: designing.** No code yet. This doc grounds a future implementation
> session. It captures the research, the hard constraints, and the chosen
> strategy.
>
> **Decided direction:** stand up the **full, official Supabase stack as a
> first-class platform** (Option B, upstream container images) on its **own
> self-contained cluster** on `watchtower`. **Do not touch atticd or Forgejo**
> in phase one — no shared cluster, no `wal_level` change to the system-of-record,
> no read-only connections into existing DBs. Integration ("browse existing data
> in Studio", "feed ClickHouse") is **deferred to post-rewrite** (see below).

## Strategic frame (why "full platform", not "ad-hoc subset")

An earlier draft of this doc argued for a minimal subset and treated RLS/auth as
"N/A for atticd." That reasoning was conditioned on **atticd and Forgejo being
fixed points** built *around*. They are not: both are slated for **substantial
rewrites**, and the same operator is shipping a **SAML product**. When you own
the apps, the question stops being "can Supabase attach to the legacy schema"
and becomes "do I want my next-gen services written *against* a hardened
auth/RLS/PostgREST substrate." The current schema/auth choices of two
hobbyist-effort projects are **not binding** if they're not good.

Consequences:

- **Deploy the real, whole thing.** It's been hardened in production for years;
  hand-rolling a Nix repackaging of six projects (and then trusting it with
  auth) would be the *ad-hoc* move. Use the upstream version-tested images.
- **RLS / GoTrue are substrate, not obstacles.** They were only "N/A" for
  retrofitting onto legacy apps. For green-field rewrites they're features. The
  auth path the operator dislikes is also the component least locked-in:
  fronting GoTrue with an external SAML IdP — or replacing GoTrue outright — is a
  known seam, not a dead end.
- **Nothing in phase one depends on atticd/Forgejo.** The migrate-or-not decision
  is genuinely deferrable because the platform stands alone first.

## What Supabase actually is

Supabase is **not** something you run *over* a Postgres. It is a constellation
of independent services that connect *to* a Postgres as **clients**, plus a
dashboard. The official self-hosting stack (`supabase/supabase/docker`) is ~10
containers:

| Service | Role | In nixpkgs? |
| --- | --- | --- |
| **Postgres** (`supabase/postgres`) | the DB, patched + ~30 extensions + seed roles/schemas | partial — `postgresql_NN` exists, the *patched image* does not |
| **Studio** | the dashboard UI (Next.js) | **no** |
| **Kong** | API gateway (one ingress for all `/auth /rest /storage /realtime`) | **no** |
| **GoTrue** (`supabase/auth`) | JWT auth API | **no** — nixpkgs `gotrue` is the *Netlify* SWT fork, **not** Supabase's |
| **PostgREST** | turns the DB into a REST API | **yes** (`postgrest`, v14) |
| **postgres-meta** | REST API the Studio UI drives (tables, roles, queries) | **no** |
| **Realtime** | Elixir WS server for DB change streams | **no** |
| **Storage** | S3-backed file API | **no** |
| **imgproxy** | image transforms for Storage | yes (`imgproxy`) but only needed by Storage |
| **Supavisor** | connection pooler | **no** |
| **edge-runtime** | Deno functions | **no** |

### The decisive finding

A **pure-Nix native-systemd** Supabase is **not currently feasible as a whole
stack**: the pieces that make Studio a *Supabase* dashboard — **Studio itself,
postgres-meta, Kong, the Supabase `auth` fork, Realtime, Storage** — are **not
packaged in nixpkgs**. Only `postgrest` and `imgproxy` are. Packaging the rest
in-repo (the `packages/zot` pattern) is a large, ongoing surface: Next.js +
Elixir/mix + Go + a Kong/OpenResty config, each version-locked to the others.

This rules out a *hand-built* pure-Nix Supabase — and that's fine, because the
decided direction is the opposite instinct: **run the upstream, version-tested
images.** Repackaging six interlocking projects (and then trusting that
repackaging with auth) would be the ad-hoc, under-hardened move. The "pure-Nix"
preference is honored where it's free (the wrapping NixOS module, the
declarative unit graph, agenix-fed secrets) — not by re-implementing Supabase.

## Phase one: full stack, self-contained, atticd/Forgejo untouched

Supabase gets its **own Postgres cluster** (the `supabase/postgres` image, with
the seed roles/schemas it expects) and the full set of services. It connects to
**nothing** in the existing fleet:

- **no** changes to `watchtower`'s system-of-record cluster (atticd's DB, the
  cache **signing keypair** in the `cache` table, the pgBackRest `main` stanza,
  the daily `pg_dumpall`) — see [PostgreSQL](../infrastructure/postgres.md) and
  [Backups](./backups.md)
- **no** `wal_level` change, **no** replication slot, **no** `studio_ro` reader
- atticd and Forgejo keep their own homes and are not connected to at all

This makes phase one genuinely low-risk: the platform stands or falls entirely
on its own cluster.

## Deferred to post-rewrite: integration

The "browse atticd/Forgejo in Studio" and "feed ClickHouse" goals are **not**
phase one. Both apps are slated for substantial rewrites, and the operator
controls a SAML product — so the right time to wire data models into Supabase
(or to write new services *against* Supabase's auth/RLS/PostgREST substrate) is
**when those models are being authored**, not as a retrofit onto schemas that
aren't binding.

When that happens, the mechanisms are known and don't change this phase:

- **Studio multi-connection** — Studio (via postgres-meta) can register
  additional Postgres connections, so browsing other clusters never requires
  moving their data into Supabase.
- **Realtime / CDC** — Postgres Changes needs the *source* cluster at
  `wal_level = logical` (a superset of the current `replica`; PITR-safe) plus a
  replication slot. For a durable ClickHouse pipeline, the hardened path is
  logical replication consumed by Debezium / PeerDB / `pg_recvlogical`; Realtime
  is best for *UI-facing liveness*. Both want `wal_level=logical` and are a
  deliberate, later change to whichever cluster is the source.
- **Auth / SAML** — GoTrue is the most replaceable component: front it with an
  external SAML IdP, or swap it. Not a lock-in.

## Implementation (as built): `virtualisation.oci-containers`, pinned in lockstep

`modules/nixos/supabase.nix` — gated `hyper-modern-nixos.supabase`, **off by
default**, in the flat import list. Docker is already on fleet-wide
(`modules/nixos/docker.nix`). Nine containers on a private `supabase` docker
network (so they resolve each other by upstream's expected names — `db`, `kong`,
`meta`, `rest`, `auth`, `realtime`, `storage`, `imgproxy`, `studio`):

- **The image set is pinned as module options** (`images.*`), defaulting to the
  exact tags from the locked upstream compose. Bump them **in lockstep** with the
  `supabase` flake input.
- **The version-coupled config files** (7 db init SQLs, the 440-line
  `kong.yml` + entrypoint, `pooler.exs`) are **not** hand-transcribed — they're
  read from the **`supabase` flake input** (`flake = false`, pinned rev) and
  bind-mounted read-only. One content-addressed checkout, version-coherent with
  the images by construction.
- **`db` is the `supabase/postgres` image**, not a native `services.postgresql` —
  its ~30 extensions + role/schema init SQL are not reproducible from
  `pkgs.postgresql`. The cluster's pgdata is a bind mount at
  `${dataDir}/db`.

> The pure-Nix-native path (`postgrest`/`imgproxy` exist; Studio, postgres-meta,
> Kong, Realtime, Storage, the Supabase `auth` fork do **not**, and `db` must be
> the patched image regardless) was considered and rejected: a full native stack
> is a multi-week packaging project with permanent maintenance, and the whole
> point is to use the hardened upstream.

## Why the DB is the one piece Nix can't cheaply own (deferred)

> **Status: deliberately deferred.** This homelab deployment is a *dress
> rehearsal for a production deployment*. For production we will likely want the
> `db` under our own control (native cluster, our PITR, our backups, no opaque
> image). That is a **battle for another day** — captured here so a future
> session starts grounded rather than re-deriving the analysis.

"The DB isn't buildable" is too blunt. There are three layers, and only the
third is genuinely hard:

| Layer | Buildable in Nix? |
| --- | --- |
| **Postgres core** | Trivially — `pkgs.postgresql_17`. |
| **Extension set** | Yes, but it's packaging a ~15-extension *distro*: `pgvector`/`postgis`/`pg_cron`/`pgaudit` are in nixpkgs; `pg_graphql`, `pg_jsonschema`, `supabase_vault`, `pgsodium`, `pg_net`, `wrappers`, `index_advisor` are Supabase's own (several `pgrx`/Rust), all version-locked to each other. |
| **Role/schema/grant bootstrap** | The teeth. Not "unbuildable" — but it means *reimplementing and version-tracking Supabase's DB init*, where subtle errors are silent and break the **other** services. |

The decisive detail is the bootstrap. `volumes/db/roles.sql` does
`ALTER USER authenticator …` / `supabase_auth_admin` / `supabase_storage_admin`
— it **alters roles that must already exist**. Nothing in the mounted
`volumes/db/*.sql` creates them; they come from **migrations baked into the
`supabase/postgres` image at build time**, which create the roles (`anon`,
`authenticated`, `service_role`, `authenticator`, `supabase_admin`, the `*_admin`
service roles), the schemas (`auth`, `storage`, `realtime`, `_realtime`,
`extensions`, `graphql`, `graphql_public`, `pgbouncer`, `_analytics`, `vault`),
the grants/RLS wiring, and the `pgsodium` server-key setup. The mounted SQL files
are *deltas on top of that baked baseline*.

So "a Postgres that works for Supabase" **is itself a Supabase deliverable**
(`supabase/postgres` is its own product — `pg_graphql`, `vault`, the role model).
Rebuilding it in Nix means re-deriving that product and chasing it forever. The
image is the version-coherent, tested artifact of all three layers at once. (Cf.
`attic-cache-keypair-restore`: the same shape of "engineer around an opaque,
stateful bootstrap an upstream stores only in its DB.")

The natural production seam, when atticd/Forgejo are rewritten *against*
Supabase: the image owns the **cluster bootstrap**; our migrations (applied via
Studio or the Supabase CLI) own the **app schema/RLS**. That cut is correct
regardless — app schema was never Nix's job. The open production question is only
whether to keep the patched image or invest in a native cluster + our own
PITR/backups for the DB tier. **Not this session.**

### Module options (as built)

```nix
hyper-modern-nixos.supabase = {
  enable = true;                              # off by default
  publicUrl = "https://studio.sju1.s4.gl";    # SUPABASE_PUBLIC_URL/API_EXTERNAL_URL/SITE_URL
  kong.httpPort = 8000;                       # Kong binds 127.0.0.1:8000 (nginx fronts it)
  kong.listenAddress = "127.0.0.1";
  dataDir = "/var/lib/supabase";              # db/ + storage/ (authoritative state)
  environmentFile = "/run/agenix/supabase-env";  # the whole secret bundle (default)
  # images.* — pinned tags; bump with the flake input.
};
```

### Secrets (one agenix bundle)

A **single** agenix env file (`supabase-env`) is fed to every container via
oci-containers `environmentFiles` — never the store. Generate it as a unit:

```sh
nix run .#gen-supabase-secrets        # → secrets/agenix/machines/supabase-env.age
```

The generator (mirrors upstream `utils/generate-keys.sh`) emits a random
`JWT_SECRET`, the HS256 API-key JWTs **derived** from it (`ANON_KEY` /
`SERVICE_ROLE_KEY`), the length-constrained random keys (`SECRET_KEY_BASE` 64,
`VAULT_ENC_KEY` 32, `PG_META_CRYPTO_KEY` 32+), `POSTGRES_PASSWORD`, dashboard
basic-auth, **and** the per-service DB connection URLs with the password embedded
(`GOTRUE_DB_DATABASE_URL`, `PGRST_DB_URI`, storage `DATABASE_URL`, …) — composed
in the generator so the password never enters the store. The derived JWTs are
only valid against the `JWT_SECRET` in the same file, so rotate as a unit
(`rotate-secret`). Registered `mkGlobalSecret` in `secrets/secrets.nix`.

### Integration with existing subsystems

- **Reverse proxy:** `hyper-modern-nixos.reverseProxy.services.studio.port = 8000;`
  on the host → real wildcard cert on `studio.sju1.s4.gl`, loopback upstream to
  Kong (Studio/auth/rest/realtime/storage are all reached *through* Kong). Same
  pattern as [registry](./registry.md).
- **State & backup:** `${dataDir}/db` and `${dataDir}/storage` are classified
  `authoritative` (persisted across an impermanence reboot AND restic'd to R2),
  **separate** from atticd. See [state model](../architecture/state-and-backup.md).
- **Exposure:** tailnet-only (firewall on fleet-wide; Kong binds loopback,
  reachable only via the nginx vhost on the tailnet/LAN). No public ports.

### Two integration details the module handles (learned at deploy)

These are the non-obvious bits that compose gets "for free" and a NixOS module
must do explicitly — both proven live on watchtower (2026-06):

- **Network aliases.** oci-containers names a container `supabase-<svc>`, but the
  services address each other by the *short* name (`db`, `meta`, `rest`, `kong`,
  …) — the names baked into `kong.yml`, `STUDIO_PG_META_URL`, and the composed DB
  URLs. Docker's embedded DNS only resolves a user-network member by its
  container name unless an alias is set, so without `--network-alias=<short>` on
  every container, every cross-service lookup (e.g. gotrue → `host=db`) fails
  `NXDOMAIN`. The `common` helper sets the alias.
- **Per-service env, not one bundle.** The agenix secret carries only the raw
  secrets. `supabase-env-split.service` sources it at activation and writes one
  `/run/supabase/env/<svc>` file per service, composing the password-embedded DB
  URLs under each image's *exact* var name — because `auth` and `storage` both
  read a var literally named `DATABASE_URL` but with a *different* role, and this
  gotrue build reads `(GOTRUE_)DATABASE_URL` rather than the compose's
  `GOTRUE_DB_DATABASE_URL`. One shared file can't satisfy that; the split can.
- **Startup-race tolerance.** oci-containers `dependsOn` is start-*order*, not a
  health *wait*. On a cold boot the db-client services start before the cluster
  finishes its (first-boot, ~minute) init + `host=db` migrations. Rather than
  trip the default 5-in-10s start limit and give up, the db-client units set
  `startLimitIntervalSec = 0` (+ `RestartSec=5s`) so they retry patiently and the
  boot converges with no manual `systemctl restart`. Verified by restarting db +
  all clients simultaneously: the stack reconverged on its own.

## Phase-one bring-up runbook

The platform stands alone — **no** atticd/Forgejo migration in phase one.

1. `nix run .#gen-supabase-secrets` → encrypts `supabase-env.age`. Commit it.
2. `enable = true` on `watchtower` (already wired), rebuild/deploy. The
   `supabase/postgres` cluster initializes its own roles/schemas on first boot;
   the service containers come up against it on the private docker network.
3. Verify `studio.sju1.s4.gl` over the tailnet (Kong gateway, basic-auth from
   the bundle: `supabase` / generated `DASHBOARD_PASSWORD`).
4. Smoke-test: create a table in Studio, hit it via PostgREST, observe a Realtime
   change event. All within Supabase's own cluster.

> **Proven live on watchtower** (2026-06): all 9 containers up
> (`db`/`meta`/`kong`/`studio` healthy); `GET /rest/v1/` → 200 with the anon
> apikey through Kong; gotrue applied its 69 migrations and `GET /auth/v1/health`
> → 200 with the anon key (401 without = correct Kong gating); the stack
> reconverges on its own after a simultaneous db+clients restart (no manual
> intervention). The nginx vhost (`studio.sju1.s4.gl`) is wired but not yet
> verified end-to-end over the tailnet.

> atticd's cluster, `attic-cache-keypair-restore`, and PITR are never touched.
> Any future migration of fleet data into (or eventing out of) Supabase is a
> separate, post-rewrite design — see "Deferred to post-rewrite" above.

## Image bumps

Update the `images.*` tags in the host/module **and** the `supabase` flake input
together (`nix flake lock --update-input supabase`, or pin a new rev), so the
config files (kong.yml, init SQL, pooler.exs) stay coherent with the images.
Upstream tests a release set together; mixing tags is unsupported.

## Open decisions / deferred

1. ~~Option B vs H~~ — **done: Option B** (full official container stack, built).
2. ~~Scope of services~~ — **done: full stack** (the rewrites target Supabase).
3. **DB tier for production** — keep the `supabase/postgres` image, or invest in a
   native cluster + our own PITR/backups? **Deferred** (this is a dress rehearsal;
   see "Why the DB is the one piece Nix can't cheaply own").
4. **Analytics tier** — include the optional Logflare + Vector
   (`docker-compose.logs.yml`) for the Log Explorer, or leave it off to save
   memory (the upstream default is off)?
4. **Second pgBackRest stanza** for the Supabase cluster, or logical dumps only?
5. **Image pinning** — pin every service image by digest in the module (matches
   the repo's determinism posture) vs. track upstream's tested tags.

## References

- Self-hosting guide: <https://supabase.com/docs/guides/self-hosting/docker>
- External-DB notes: same guide, "Accessing / Exposing Postgres"
- Existing patterns to mirror: [registry (zot)](./registry.md),
  [PostgreSQL](../infrastructure/postgres.md),
  [networking](../architecture/networking.md)
