#!/usr/bin/env bash
# Render the fleet_admins ssh keys from the user registry to admin-recipients.json
# — the agenix user-recipient set. Run after changing admin membership in
# modules/flake/registry/data/users.dhall, then re-key: `nix run .#rekey-secrets`.
#
# n.b. runs from the repo's secrets/ dir (mkSecretApp cd's here); writes
# ./admin-recipients.json. The admin-recipients-sync flake check fails if this
# file drifts from the registry.
set -euo pipefail

export LC_ALL=C.UTF-8 LANG=C.UTF-8

registry="$(git rev-parse --show-toplevel)/modules/flake/registry/data/render-users.dhall"

dhall-to-json --file "$registry" |
  jq -S '[.[] | select(.groups | index("fleet_admins")) | .sshKeys[]] | unique' \
    >admin-recipients.json

echo "✓ wrote $(pwd)/admin-recipients.json"
jq -r '.[]' admin-recipients.json | sed 's/^/  /'
