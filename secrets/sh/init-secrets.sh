#!/usr/bin/env bash

cd "$(dirname "$0")/.."
nix eval --impure --json --expr 'builtins.attrNames (import ./secrets.nix)' |
  jq -r '.[]' |
  while read -r secret; do
    echo "checking file for $secret"
    path="$secret"
    dir="$(dirname "$path")"
    mkdir -p "$dir"
    if [ ! -f "$path" ]; then
      echo "creating file for $secret"
      echo "UNINITIALIZED" | EDITOR="tee" agenix -e "$path"
    fi
  done
