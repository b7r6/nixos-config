# PostgreSQL

PostgreSQL (and Redis) from `modules/nixos/postgres.nix`, under
`hyper-modern-nixos.databases`. **Off by default.**

This module previously enabled postgres unconditionally on *every* host. It is
now **opt-in**: the fleet runs exactly one shared postgres (on
[`watchtower`](./attic.md)) backing the central [attic](./attic.md) cache's
metadata. Other hosts don't need a local postgres.

```nix
hyper-modern-nixos.databases.postgres = {
  enable = true;
  tailnet.enable = true;
  ensureDatabases = [ "atticd" ];
  ensureUsers = [ { name = "atticd"; ensureDBOwnership = true; } ];
};
```

Package defaults to `postgresql_16`.

## Tailnet exposure model

When `tailnet.enable` is set, exposure is gated at **two layers** (defense in
depth):

1. **Firewall** — port `5432` is opened **only** on `tailnet.interface`
   (`tailscale0`), via `networking.firewall.interfaces`. Postgres is more
   sensitive than a pull cache, so the host should re-enable its firewall
   (`hyper-modern-nixos.network.firewall.enable = true`) so this
   interface-scoped rule actually bites. The rest of the fleet runs
   firewall-off; the DB host opts back in (watchtower does exactly this).
2. **`pg_hba`** — md5 auth permitted only from loopback + the tailnet CIDRs.

`enableTCPIP` is driven by `tailnet.enable` (it sets `listen_addresses = "*"`,
the blessed NixOS knob). `listen_addresses` takes addresses, not interface
names, so binding the specific tailscale IP isn't possible declaratively —
`"*"` + firewall + `pg_hba` is the pattern. The generated `pg_hba`:

```
# TYPE  DATABASE  USER  ADDRESS              METHOD
local   all       all                        peer
host    all       all   127.0.0.1/32         md5
host    all       all   ::1/128              md5
host    all       all   100.64.0.0/10        md5   # tailscale CGNAT (IPv4)
host    all       all   fd7a:115c:a1e0::/48  md5   # tailscale ULA (IPv6)
```

The CIDRs come from `tailnet.cidrs` (defaults above). atticd replicas on other
hosts connect over MagicDNS (`watchtower.osiris-walleye.ts.net`).

## Declarative databases & users

- `ensureDatabases` → `services.postgresql.ensureDatabases`
- `ensureUsers` → `services.postgresql.ensureUsers`

These are **peer-auth only** — `ensureUsers` **cannot set a password**. For
password auth use `rolePasswords` (below).

## `rolePasswords`: declarative passwords from agenix

Since `ensureUsers` can't set passwords, `rolePasswords` wires a post-start
oneshot (`postgresql-role-passwords.service`) that runs an idempotent
`ALTER ROLE <name> … PASSWORD …` for each entry, sourcing the password from an
**agenix secret** at runtime — never the store.

```nix
hyper-modern-nixos.databases.postgres.rolePasswords.atticd = {
  secret = "atticd-rs256";   # agenix secret NAME → /run/agenix/atticd-rs256
  var    = "PGPASSWORD";     # env var within the secret holding the password
};
```

Single source of truth: the **same** secret the client (e.g.
[atticd](./attic.md)) reads `PGPASSWORD` from, so they can't drift.

The module also **grants the postgres user group-read** on the named secret
(`age.secrets.<name>.group = "postgres"`, `mode = "0440"`), so the
`postgres`-run oneshot can source it with no manual `chown`. The secret stays
root-owned; atticd reads the same file via systemd `EnvironmentFile` (as root),
so group-read doesn't affect it. The `age.secrets` grant is only emitted when
`rolePasswords` is non-empty (so a host without agenix — e.g. a VM test — never
touches the age option).

## Redis

`hyper-modern-nixos.databases.redis.enable` brings up `services.redis.servers.""`.
Off by default.
