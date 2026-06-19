#!/usr/bin/env bash
# verify every secret decrypts with the operator's identities (agenix + passage).
set -euo pipefail

identities=()
for k in ~/.ssh/id_ed25519 ~/.ssh/id_ed25519_b7r6 ~/.ssh/id_ed25519_yubikey; do
  [ -f "$k" ] && identities+=(-i "$k")
done

if [ "${#identities[@]}" -eq 0 ]; then
  echo "✗ no operator SSH identities found in ~/.ssh"
  exit 1
fi

errors=0

printf "// secrets // validate (agenix)\n\n"
while read -r secret; do
  if rage -d "${identities[@]}" "$secret" >/dev/null 2>&1; then
    echo "✓ $secret"
  else
    echo "✗ $secret (failed to decrypt)"
    errors=$((errors + 1))
  fi
done < <(find agenix -name "*.age" -type f | sort)

if [ -d passage-store ]; then
  printf "\n// secrets // validate (passage)\n\n"
  while read -r secret; do
    if rage -d "${identities[@]}" "$secret" >/dev/null 2>&1; then
      echo "✓ $secret"
    else
      echo "✗ $secret (failed to decrypt)"
      errors=$((errors + 1))
    fi
  done < <(find passage-store -name "*.age" -type f | sort)
fi

echo
if [ "$errors" -eq 0 ]; then
  echo "✓ all secrets valid and accessible"
else
  echo "✗ $errors secret(s) failed validation"
  exit 1
fi
