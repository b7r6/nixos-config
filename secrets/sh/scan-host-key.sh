#!/usr/bin/env bash
# fetch a host's ed25519 SSH host key for pasting into keys.nix.
# usage: scan-host-key <hostname>
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "usage: scan-host-key <hostname>"
  echo
  echo "add the output under hosts.<hostname> in keys.nix, then rekey-secrets."
  exit 1
fi

echo "// scanning // $1 // ed25519 host key"
key=$(ssh-keyscan -t ed25519 -T 5 "$1" 2>/dev/null | grep -v '^#' | awk '{print $2, $3}')

if [ -z "$key" ]; then
  echo "✗ no response — is $1 reachable? (try over the tailnet)"
  exit 1
fi

echo
echo "add to keys.nix:"
echo
echo "    $1 = ["
echo "      \"$key\""
echo "    ];"
