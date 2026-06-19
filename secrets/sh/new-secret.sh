#!/usr/bin/env bash
# create a new secret from $EDITOR input. usage: new-secret <path>
# remember to also add it to secrets.nix (with mkGlobalSecret / mkSecret).
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "usage: new-secret <path>"
  echo
  echo "examples:"
  echo "  new-secret agenix/machines/some-key.age"
  echo "  new-secret agenix/users/b7r6/some-key.age"
  exit 1
fi

if [ -f "$1" ]; then
  echo "error: secret '$1' already exists — use edit-secret to modify it"
  exit 1
fi

mkdir -p "$(dirname "$1")"

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

echo "# enter your secret below (lines starting with # are removed)" >"$tmpfile"
"${EDITOR:-nvim}" "$tmpfile"

grep -v '^#' "$tmpfile" | agenix -e "$1"
echo "✓ created $1"
echo
echo "now declare it in secrets.nix, e.g.:"
echo "  \"$1\".publicKeys = mkGlobalSecret;   # or mkSecret [ \"host\" … ]"
