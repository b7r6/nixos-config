#!/usr/bin/env bash
# re-encrypt every secret to the current recipient set in secrets.nix.
# run this after changing keys.nix (added/rotated host or user keys).
set -euo pipefail

agenix -r && echo "✓ all secrets rekeyed to current keys.nix recipients"
