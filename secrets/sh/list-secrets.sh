#!/usr/bin/env bash

cd "$(dirname "$0")/.."
nix eval --impure --json --expr 'builtins.attrNames (import ./secrets.nix)' |
  jq -r '.[]' |
  while read -r secret; do
    if [ -f "$secret" ]; then
      echo "$secret exists"
    else
      echo "$secret is specified but does not exist"
    fi
  done
