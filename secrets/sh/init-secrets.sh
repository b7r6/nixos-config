#!/usr/bin/env bash
# create (empty) any secret declared in secrets.nix that is missing on disk,
# so a fresh checkout can be populated incrementally. edit-secret to fill them.
set -euo pipefail

echo "// initializing // missing secrets"

if [ ! -f secrets.nix ]; then
  echo "✗ secrets.nix not found (run from the secrets/ directory)"
  exit 1
fi

created=0
while read -r secret; do
  if [ ! -f "$secret" ]; then
    echo "creating $secret"
    mkdir -p "$(dirname "$secret")"
    echo "" | agenix -e "$secret"
    created=$((created + 1))
  fi
done < <(grep -o '"[^"]*\.age"' secrets.nix | tr -d '"')

if [ "$created" -eq 0 ]; then
  echo "✓ nothing missing — all declared secrets exist"
else
  echo "✓ created $created placeholder secret(s); edit-secret to fill them"
fi
