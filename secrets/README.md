# // psv4 // secrets // bootstrap key and other secrets management

## Overview

This is the secrets management environment for `ps-v4`. We use `age` for encryption because:

- It's simpler than most alternatives (SOPS and GPG are powerful but complex)
- It works with SSH keys (which everyone already has)
- It supports Yubikeys (which we should star using)

## Quick Start

```bash
# Enter the secrets shell
cd secrets            # if you have direnv installed
nix develop .#secrets # if you want to do things manually and nest shells or whatever

# see what secrets exist
list-secrets

# view a secret
view-secret secrets/prod/database-url.age

# edit a secret
edit-secret secrets/prod/database-url.age

# create a new secret
new-secret secrets/prod/new-api-key.age

# update/rekey the secrets to have new readers or
# exclude old readers from new secrets (e.g. we're rotating a tailscale key)
rekey-secret secrets/prod/new-api-key.age
```

## How It Works

### Keys

- Public keys live in `keys.json` (or `keys.nix`)
- Your SSH key is your identity
- Secrets are encrypted to multiple recipients

### File Structure

```
secrets/
├── cc1
│   ├── accounts.json.age
│   ├── agiti.docker.compose.yaml.age
│   ├── ...
│   └── venue-keys.age
├── cc7
│   ├── accounts.json.age
│   ├── ...
│   └── venue-keys.age
├── datadog-psv4-service-account-credentials.json.age
├── datadog-psv4-service-account-key.txt.age
├── haruko-api-credentials.json.age
├── ...
├── tardis-keys-kosta-master.json.age
└── tardis-key-tokyo-dev.txt.age
```

## Common Tasks

### Adding a New Team Member

1. Get their SSH public key
2. Add to `keys.json`:
   ```json
   {
     "users": {
       "newperson": "ssh-ed25519 AAAAC3..."
     }
   }
   ```
3. Run `sync-json-keys-to-nix`
4. Run `rekey-secrets` to give them access

### Rotating a Secret

```bash
# Creates timestamped backup and opens editor
rotate-secret secrets/prod/api-key.age
```

### Checking What Changed

```bash
# See what secrets changed in last commit
diff-secrets HEAD~1

# Validate all secrets still decrypt
validate-secrets
```

### Integration with NixOS

```nix
# In your NixOS configuration
age.secrets.database-url = {
  file = ../../secrets/prod/database-url.age;
  owner = "myapp";
  group = "myapp";
};

# Then use it
services.myapp = {
  environmentFile = config.age.secrets.database-url.path;
};
```

### Emergency Access

If you can't decrypt a secret but have the repo:

1. Ask in `#security`, someone will have the DevOps 1Password (search "psv4 user - o\\perator master
   ssh key")

## Security Model

- **Five Dollar Wrench Guy**: if it's easier to get access with a wrench, that's your threat model
- **Handle Your Laptop Rule**: realistic attacks with computers will be stolen or breached laptops
- **Encryption**: `age` with `SSH` keys, it's already how you log in
- **Access Control**: Via key management in `keys.json`, this is for hosts so that a compromised
  host can't jack the tailnet
- **Audit**: `git` history shows all changes / TailScale netlogs document everything
- **Backup**: `git` = distributed and centralized backup
- **Recovery**: multiple team members can decrypt and the master key is in `1password`

## GUIDELINES

- most "secrets" aren't, we're better off being careful with a few than sloppy with 100 or 1000
- if access requires breaching the SSO of TailScale, it's not a secret.
- don't write your own crypto: use the tools done by people who work at security companies
- the only `SSL` library that isn't backdoored by 9 different countries is `libressl`, and it's
  compatible with everything
- if you're able to use the tailnet, plaintext is fine and actually better because the netlogs will
  be transparent
- if you're not able to use the tailnet, then use `TLS` via `HTTPS` and `letsencrypt` certs
  auto-issued by `funnel` or `serve`
- if you're not able to use the tailnet or `HTTPS` with a TailScale-issued `TLS` certificate, use
  `libsodium`.
- if you're doing something unsupported by `libsodium`, stop.

### Actual Secrets

**Real Secrets** (protect these):

- The 1Password master key
- TailScale Auth Keys with Pre-Existing Access Tags
- Private `SSH` Keys of Operators and Hosts
- API *secrets* and *passphrases* for venues *only*, the key is a `UUID`

**Not Secrets**

- 1. Anything in environment variables on a host (easiest `pwn` evar)
- 2. That's everything

## Troubleshooting

### "Failed to decrypt"

- Are you using the right SSH key? Check `ssh-add -l`
- Were you added to keys.json? Ask someone to rekey-secrets
- Is your SSH key password-protected? `ssh-add` first

### "Secret not found"

- Check the path: `list-secrets`
- Maybe it's in a different environment (prod vs dev)

### "Permission denied"

- The secrets shell needs access to your SSH key
- Try: `ssh-add ~/.ssh/id_ed25519`

## Philosophy

We keep secrets management simple because:

1. Complex systems breed workarounds
2. If it's annoying, people won't use it
3. Git + age is auditable and recoverable
4. Your SSH key is already your identity

Remember: The best secret is one that can be rotated easily.
