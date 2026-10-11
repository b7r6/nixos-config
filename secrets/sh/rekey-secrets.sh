#!/usr/bin/env bash
# re-encrypt every secret to the current recipient set in secrets.nix.
# run this after changing keys.nix (added/rotated host or user keys).
#
# agenix only looks at ~/.ssh/id_rsa and ~/.ssh/id_ed25519 by default; the
# operator identities in this repo are named differently (see
# modules/flake/devshell.nix), so pass every one that exists explicitly.
set -euo pipefail

identities=()
for i in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519_b7r6" "$HOME/.ssh/id_ed25519_yubikey"; do
  [[ -r "$i" ]] && identities+=(-i "$i")
done

agenix -r "${identities[@]}" && echo "✓ all secrets rekeyed to current keys.nix recipients"
