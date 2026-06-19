#!/usr/bin/env bash
# write ~/.passage/identities from the operator's SSH keys, so `passage`
# (the interactive store) can decrypt entries under secrets/passage-store/.
set -euo pipefail

mkdir -p ~/.passage
: >~/.passage/identities

found=0
for key in ~/.ssh/id_ed25519 ~/.ssh/id_ed25519_b7r6 ~/.ssh/id_ed25519_yubikey; do
  if [ -f "$key" ]; then
    echo "$key" >>~/.passage/identities
    echo "added $key"
    found=$((found + 1))
  fi
done

if [ "$found" -eq 0 ]; then
  echo "✗ no operator SSH keys found in ~/.ssh"
  exit 1
fi

echo
echo "✓ passage identities configured"
echo "  point PASSAGE_DIR at: $(pwd)/passage-store"
