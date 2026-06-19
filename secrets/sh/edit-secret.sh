#!/usr/bin/env bash
# edit a secret in $EDITOR (creating it if absent). usage: edit-secret <path>
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "usage: edit-secret <secret-path>"
  echo
  echo "available secrets:"
  find agenix -name "*.age" -type f | sort | sed 's/^/  /'
  exit 1
fi

echo "// editing // secret // $1"

if [ ! -f "$1" ]; then
  echo "creating new secret: $1"
  mkdir -p "$(dirname "$1")"
fi

agenix -e "$1"
