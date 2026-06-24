# Dev shells

The flake ships two dev shells:

- **`default`** — the everyday shell, with the [`nh`](https://github.com/viperML/nh) workflow
  commands and the operator's **user secrets** auto-loaded into the environment.
- **`secrets`** — the agenix/passage administration surface.

## The default shell

```bash
nix develop          # or: direnv allow (the repo has an .envrc)
```

Wired from `devshell.toml` (via `modules/flake/default.nix`, which imports it into
`devshells.default`). Commands:

| Command | Category | Runs |
| --- | --- | --- |
| `switch-os` | development | `nh os switch .` |
| `switch-home` | development | `nh home switch .` |
| `treefmt` | development | `nix fmt` |
| `tailscale-up-current-user` | network | `sudo tailscale up --operator=$(whoami)` |
| `list-tailscale-networks` | network | `sudo tailscale switch --list` |
| `build-usb` | installer | `./scripts/build-usb.sh` |

### Auto-loaded user secrets (agenix-shell)

On shell entry, `modules/flake/devshell.nix` uses **agenix-shell** to decrypt the operator's *user*
secrets (under `secrets/agenix/users/b7r6/`) to a tmpfs under `$XDG_RUNTIME_DIR` and export them.
Decryption uses whichever of these SSH identities is present: `~/.ssh/id_ed25519`,
`~/.ssh/id_ed25519_b7r6`, `~/.ssh/id_ed25519_yubikey`.

Each secret is exported **twice** — the contents as `<NAME>` (good for tokens) and the tmpfs path as
`<NAME>_PATH` (good for file-shaped secrets):

| Var | Source | Shape |
| --- | --- | --- |
| `HF_TOKEN` | `hf-token.age` | token |
| `ATUIN_KEY` | `atuin-key.age` | token |
| `NETRC` / `NETRC_PATH` | `netrc.age` | file |
| `RCLONE_CONF` / `RCLONE_CONF_PATH` | `rclone-conf.age` | file |

**Scope is deliberate:** only the user secrets the operator has a license to are loaded. Machine
secrets (restic password, atticd RS256, R2 env files) are *not* loaded into the interactive shell —
they belong to systemd services on the hosts, decrypted by host keys at activation. See
[Secrets (agenix)](../infrastructure/secrets.md).

## The secrets shell

```bash
nix develop .#secrets
```

Provided by `secrets/default.nix` (a flake-parts module imported in `modules/flake/default.nix`).
Every admin command is a real shellcheck/shfmt- clean script under `secrets/sh/`, wrapped as a
`writeShellApplication` with pinned `runtimeInputs`, and exposed **both** as a shell command **and**
a flake app (`nix run .#<name>`). Each command is git-root-aware: it `cd`s into the repo's
`secrets/` and sets `RULES=secrets/secrets.nix` so `agenix` finds its recipients no matter where you
invoke it.

| Command | Purpose |
| --- | --- |
| `list-secrets` | List all defined secrets |
| `view-secret` | Decrypt + print a secret |
| `edit-secret` | Decrypt to `$EDITOR`, re-encrypt on save |
| `new-secret` | Create a new secret |
| `rotate-secret` | Re-generate / replace a secret's contents |
| `rekey-secrets` | Re-encrypt every secret to the current `keys.nix` recipients (`agenix -r`) |
| `init-secrets` | Bootstrap the secret tree |
| `validate-secrets` | Sanity-check definitions vs. files |
| `scan-host-key` | `ssh-keyscan -t ed25519 <host>` → line for `keys.nix` |
| `init-passage` | Bootstrap the passage store |
| `secrets-usage` | Print the usage banner (also the shell's `shellHook`) |

Run any of them as a flake app without entering the shell, e.g.:

```bash
nix run .#scan-host-key shimmer
nix run .#rekey-secrets
```

The shell also brings `agenix`, `age`, `rage`, `ssh-to-age`, `passage`, `age-plugin-yubikey`, and
`yubikey-manager` onto `PATH` for manual operations.
