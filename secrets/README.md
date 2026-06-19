# // hyper-modern-nixos // secrets

## Overview

Two complementary systems for secrets management:

1. **Agenix** - Declarative secrets deployed by NixOS/home-manager at activation time
2. **Passage** - Interactive password store for emacs/CLI use (age-based `pass` alternative)

Both use `age` encryption with your SSH keys.

## Directory Structure

```
secrets/
├── keys.nix                    # Public keys for users and hosts
├── secrets.nix                 # Agenix rules (what's encrypted to whom)
├── agenix/                     # NixOS-deployed secrets
│   ├── machines/               # Machine-level secrets (Tailscale, etc.)
│   │   └── tailscale-auth-key.*.age
│   └── users/                  # User secrets deployed to $HOME
│       └── b7r6/
│           ├── netrc.age       # API credentials for CLI tools
│           ├── atuin-key.age   # Shell history sync key
│           └── ...
└── passage-store/              # Interactive secrets (emacs/CLI)
    ├── .age-recipients         # Who can decrypt (SSH pub keys)
    └── api/                    # API keys for emacs gptel, etc.
        └── openrouter-*.age
```

## Quick Start

```bash
# Enter the secrets shell
cd secrets
# (direnv auto-activates, or: nix develop ..#secrets)

# List all secrets
list-secrets

# View an agenix secret
view-secret agenix/users/b7r6/netrc.age

# Edit an agenix secret
edit-secret agenix/users/b7r6/netrc.age

# Use passage for interactive secrets
passage list
passage show api/openrouter-emacs
passage insert api/new-key
```

## Agenix (NixOS-Deployed Secrets)

Secrets in `agenix/` are deployed by NixOS at activation time:

- Machine secrets → `/run/agenix/<name>`
- User secrets → `$HOME/.config/agenix/<name>` (via home-manager)

### Adding a New Agenix Secret

1. Create the secret file:

   ```bash
   new-agenix-secret agenix/users/b7r6/new-secret.age
   ```

2. Add to `secrets.nix`:

   ```nix
   "agenix/users/b7r6/new-secret.age".publicKeys = b7r6Everywhere;
   ```

3. Reference in your NixOS/home-manager config:

   ```nix
   age.secrets.new-secret = {
     file = ../../../secrets/agenix/users/b7r6/new-secret.age;
     path = "${config.home.homeDirectory}/.new-secret";
   };
   ```

### Adding a New Host

1. Get the host's SSH key:

   ```bash
   scan-host-key hostname
   # or on the host: cat /etc/ssh/ssh_host_ed25519_key.pub
   ```

2. Add to `keys.nix`:

   ```nix
   hosts = {
     hostname = [
       "ssh-ed25519 AAAAC3..."
     ];
   };
   ```

3. Rekey secrets so the host can decrypt:

   ```bash
   rekey-secrets
   ```

## Passage (Interactive Secrets)

Passage secrets in `passage-store/` are for interactive use - emacs, CLI tools, etc.

The store is checked into git and read directly from the repo (no symlinks).

### Environment Setup

Your shell sets these automatically via home-manager:

```bash
PASSAGE_DIR=~/src/nixos-config/secrets/passage-store
PASSAGE_IDENTITIES_FILE=~/.passage/identities
```

### Emacs Integration

Emacs uses passage for:

- **gptel** - OpenRouter API keys (`api/openrouter-emacs`)
- **auth-source-pass** - Generic credential lookup
- **password-store.el** - Browse/copy/insert passwords

Keybindings:

- `C-c p p` - Browse password store
- `C-c p c` - Copy password
- `C-c p g` - Generate password
- `C-c p i` - Insert new password

### Adding Passage Secrets

```bash
# From CLI
passage insert api/new-service

# From emacs
M-x password-store-insert
```

## Key Management

### keys.nix Structure

```nix
{
  users = {
    b7r6 = [
      "ssh-ed25519 AAAAC3..." # id_ed25519
      "ssh-ed25519 AAAAC3..." # id_ed25519_b7r6
    ];
  };

  hosts = {
    weyl = [ "ssh-ed25519 AAAAC3..." ];
    shimmer = [ "ssh-ed25519 AAAAC3..." ];
    # ...
  };
}
```

### Who Can Decrypt What

- **User secrets** (`agenix/users/b7r6/*`): User's SSH keys + all configured hosts
- **Machine secrets** (`agenix/machines/*`): User's SSH keys + relevant hosts
- **Passage secrets**: Only user's SSH keys (defined in `.age-recipients`)

## Troubleshooting

### "Failed to decrypt"

```bash
# Check your SSH keys are loaded
ssh-add -l

# Verify you can decrypt
rage -d -i ~/.ssh/id_ed25519 agenix/users/b7r6/netrc.age

# Check identities file
cat ~/.passage/identities
```

### Passage not finding secrets

```bash
# Check PASSAGE_DIR
echo $PASSAGE_DIR

# Should point to repo, not ~/.passage/store
# If wrong, re-run home-manager switch
```

### After adding a host key

```bash
# Rekey so the host can decrypt its secrets
cd secrets
rekey-secrets
git add -A && git commit -m "rekey for new host"
```

## Security Notes

- SSH keys are your identity - protect them
- Passage store is checked into git - only put non-critical secrets there
- Critical secrets (Tailscale auth, etc.) go in agenix with proper host scoping
- The master decryption capability is your SSH private key
