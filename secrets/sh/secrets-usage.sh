#!/usr/bin/env bash
# MOTD / help banner for the secrets devshell and `nix run .#secrets-usage`.
set -euo pipefail

cat <<'USAGE'
// hypermodern // secrets

  agenix (NixOS-deployed):
    list-secrets      // show all secrets + encryption status
    view-secret       // decrypt a secret to stdout (usage: view-secret <path>)
    edit-secret       // edit a secret with $EDITOR
    new-secret        // create a new secret
    rotate-secret     // timestamped backup, then re-edit
    rekey-secrets     // re-encrypt all to current keys.nix recipients
    init-secrets      // create any secrets declared in secrets.nix but missing
    validate-secrets  // verify every secret decrypts with your keys

  keys:
    scan-host-key     // fetch a host's ed25519 key for keys.nix

  passage (interactive / emacs):
    init-passage      // write ~/.passage/identities from your SSH keys
    passage list|show|insert

  every command is also a flake app, e.g.:  nix run .#rekey-secrets
USAGE
