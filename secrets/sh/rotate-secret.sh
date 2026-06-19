#!/usr/bin/env bash
# rotate a secret: timestamped backup, then re-edit. usage: rotate-secret <path>
# NOTE: backups are written next to the secret as <name>.backup.<ts>; they are
# gitignored (see secrets/.gitignore) so plaintext-adjacent copies never commit.
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "usage: rotate-secret <secret-path>"
  echo
  echo "available secrets:"
  find agenix -name "*.age" -type f | sort | sed 's/^/  /'
  exit 1
fi

if [ ! -f "$1" ]; then
  echo "error: secret '$1' not found"
  exit 1
fi

backup="${1}.backup.$(date +%Y%m%d-%H%M%S)"
cp "$1" "$backup"
echo "✓ backup created: $backup"

agenix -e "$1"
echo "✓ secret rotated"
