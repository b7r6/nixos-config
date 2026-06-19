#!/usr/bin/env bash
# decrypt a secret to stdout (no editor). usage: view-secret <path>
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "usage: view-secret <secret-path>"
  echo
  echo "available secrets:"
  find agenix -name "*.age" -type f | sort | sed 's/^/  /'
  echo
  echo "for passage secrets use: passage show <entry>"
  exit 1
fi

if [ ! -f "$1" ]; then
  echo "error: secret '$1' not found"
  echo
  echo "available secrets:"
  find agenix -name "*.age" -type f | sort | sed 's/^/  /'
  exit 1
fi

# agenix's editor path round-trips through RULES; using cat as EDITOR prints
# the decrypted plaintext to stdout without rewriting the file.
EDITOR="cat" agenix -e "$1"
