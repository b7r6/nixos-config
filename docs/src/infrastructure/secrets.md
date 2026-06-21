# Secrets (agenix)

Secrets are managed with [agenix](https://github.com/ryantm/agenix) (age + SSH
recipient keys) plus an interactive `passage` store for emacs/CLI use. Source
lives under [`secrets/`](https://github.com/anomalyco/weapon).

- [`secrets/keys.nix`](#keysnix-single-source-of-truth) — recipient public keys
- [`secrets/secrets.nix`](#recipient-helpers) — per-secret recipient sets (the agenix RULES file)
- [`secrets/default.nix`](#admin-devshell--flake-apps) — the admin devShell + flake apps
- `secrets/sh/*.sh` — the actual management commands

No plaintext secret value ever lives in the Nix store. Decrypted machine
secrets land at `/run/agenix/<name>` (root, `0400`); user secrets are deployed
by the home-manager agenix module.

## `keys.nix`: single source of truth

`secrets/keys.nix` is **data only** — two attrsets mapping a name to a list of
`ssh-ed25519` public keys. agenix consumes ed25519 SSH keys directly (no
ssh-to-age conversion needed).

```nix
{
  users = { b7r6 = [ "ssh-ed25519 …" /* primary, named, yubikey */ ]; };
  hosts = {
    ultraviolence = [ "ssh-ed25519 …" ];
    watchtower    = [ "ssh-ed25519 …" ];
    weyl          = [ "ssh-ed25519 …" ];
    guccimane     = [ "ssh-ed25519 …" ];
    shimmer       = [ "ssh-ed25519 …" ];  # aarch64 DGX Spark
    gossamer      = [ "ssh-ed25519 …" ];  # non-NixOS Nix node
    shannon       = [ ];                  # laptop, powered down — TODO scan
  };
}
```

A host can only **decrypt** a secret once (a) its key is listed here, **and**
(b) the secret has been re-keyed to include it (`nix run .#rekey-secrets`).
Adding a host to the fleet is: scan its key → add to `keys.nix` → rekey.

The host key is the box's own `/etc/ssh/ssh_host_ed25519_key`, so machine
secrets decrypt automatically at activation with no extra key material.

## Recipient helpers

`secrets/secrets.nix` imports `keys.nix` and derives recipient sets from it, so
adding a host + re-keying is all it takes to extend access — no per-secret
edits.

```nix
allUserKeys     = concatLists (attrValues keys.users);   # every operator key
configuredHosts = filter (h: keys.hosts.${h} != [ ]) (attrNames keys.hosts);

# all users + the named hosts (future least-privilege scoping)
mkSecret       = hostList: allUserKeys ++ concatMap (h: keys.hosts.${h} or []) hostList;
# all users + every configured host (skips empty TODO stubs)
mkGlobalSecret = mkSecret configuredHosts;
```

- Every secret is **always** encrypted to all user keys, so any operator can
  edit/rekey.
- `mkSecret [ "host" … ]` adds named hosts; `mkGlobalSecret` adds every
  configured host.
- Today everything is `mkGlobalSecret` (single operator, mutually-trusted
  fleet). `mkSecret` exists so least-privilege scoping is a one-line change per
  secret rather than a structural refactor.

## Layout

```
secrets/
├── keys.nix                       # recipient pubkeys (source of truth)
├── secrets.nix                    # RULES: per-secret recipient sets
├── default.nix                    # admin devShell + flake apps
├── sh/*.sh                        # management commands
├── agenix/
│   ├── machines/<secret>.age      # machine secrets → /run/agenix/ (root, 0400)
│   └── users/b7r6/<secret>.age    # user secrets → home-manager agenix
└── passage-store/                 # interactive secrets (NOT agenix-managed)
```

## Machine secrets

Decrypted to `/run/agenix/<name>` on the target host. Names only below — values
are never stored:

| Secret | Purpose |
|---|---|
| `tailscale-auth-key` | declarative tailnet enrollment ([Tailscale](./tailscale.md)) |
| `restic-password` | restic repo passphrase ([Backups](./backups.md)) — **losing this = unrecoverable backups** |
| `restic-r2-env.ultraviolence` | per-host restic R2 backend env (`RESTIC_REPOSITORY` + R2 creds) |
| `restic-r2-env.watchtower` | per-host restic R2 backend env |
| `nativelink-r2-env` | nativelink R2 CAS creds ([Remote execution](./nativelink.md)) |
| `atticd-rs256` | atticd RS256 JWT signing secret + `PGPASSWORD` + R2 `AWS_*` ([attic](./attic.md)) |
| `attic-push-token` | raw JWT for `watch-store` auto-push to the `hypermodern` cache |
| `attic-cache-keypair` | the cache's `NixKeypair` (restored into postgres on activation) |

## User secrets

Deployed via the home-manager agenix module under `agenix/users/b7r6/`:

| Secret | Purpose |
|---|---|
| `netrc` | machine credentials (`~/.netrc`) |
| `atuin-key` | atuin shell-history sync key |
| `hf-token` | HuggingFace token |
| `rclone-conf` | full `rclone.conf` (R2 remote + creds), also used by the system rclone mount |

## Admin devShell + flake apps

Every management command in `secrets/sh/` is a `shellcheck`/`shfmt`-clean
script, wrapped as a `writeShellApplication` with pinned `runtimeInputs`
(`agenix`, `age`, `rage`, `ssh-to-age`, `openssh`, …) and exposed **both** as a
package in the `secrets` devShell and as a standalone flake app.

Each command is git-root-aware: it locates the repo's `secrets/` directory,
`cd`s there, and exports `RULES=$SECRETS_DIR/secrets.nix` so `agenix` finds the
rules file no matter where you invoke it.

```sh
nix develop .#secrets          # drop into the admin shell (prints the usage banner)
nix run .#rekey-secrets        # …or run any command as a flake app
```

| Command / app | What it does |
|---|---|
| `list-secrets` | list every `.age` + on-disk status; flags secrets declared in `secrets.nix` but **missing** on disk |
| `view-secret <path>` | decrypt to stdout (uses `EDITOR=cat`, no rewrite) |
| `edit-secret <path>` | open in `$EDITOR` (creating if absent) |
| `new-secret <path>` | create from `$EDITOR` input; reminds you to add it to `secrets.nix` |
| `rotate-secret <path>` | timestamped (gitignored) backup, then re-edit |
| `rekey-secrets` | `agenix -r` — re-encrypt **all** secrets to the current `keys.nix` recipients |
| `init-secrets` | create empty placeholders for any secret declared but missing |
| `validate-secrets` | verify every secret decrypts with the operator's `~/.ssh` identities |
| `scan-host-key <host>` | `ssh-keyscan` a host's ed25519 key, formatted for pasting into `keys.nix` |
| `init-passage` | write `~/.passage/identities` from your SSH keys |
| `secrets-usage` | the help banner |

### Common flows

```sh
# add a host: scan → paste into keys.nix → rekey
nix run .#scan-host-key -- newbox
$EDITOR secrets/keys.nix
nix run .#rekey-secrets

# create + declare a new machine secret
nix run .#new-secret -- agenix/machines/some-key.age
# then add to secrets.nix:  "agenix/machines/some-key.age".publicKeys = mkGlobalSecret;
nix run .#rekey-secrets

# verify everything decrypts with your keys
nix run .#validate-secrets
```

The operator's **user** secrets (`HF_TOKEN`, `NETRC_PATH`, …) are auto-loaded
into the *default* devshell env separately, by
`modules/flake/devshell.nix` via `agenix-shell` — that is independent of this
admin surface.

## How a host wires a secret

A host declares the agenix secret (pointing at the `.age` file in the repo) and
imports the agenix NixOS module; agenix decrypts it to `/run/agenix/<name>` at
activation. Modules then reference that runtime path — never the store.

```nix
# configurations/nixos/<host>/configuration.nix
imports = [ inputs.agenix.nixosModules.default ];

age.secrets.tailscale-auth-key.file =
  ../../../secrets/agenix/machines/tailscale-auth-key.age;

hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
```

Secrets that must be readable by a non-root service set `group`/`mode` — e.g.
the [postgres](./postgres.md) `rolePasswords` feature grants the `postgres`
group `0440` read on the password secret so a `postgres`-run oneshot can source
it.
