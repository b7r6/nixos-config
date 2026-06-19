#!/usr/bin/env bash
# list every agenix secret + its on-disk status, and flag any secret that is
# declared in secrets.nix (the RULES file) but missing on disk.
set -euo pipefail

echo "// secrets // agenix (NixOS-deployed)"
echo
printf "%-55s %s\n" "SECRET" "STATUS"
printf "%-55s %s\n" "------" "------"

find agenix -name "*.age" -type f 2>/dev/null | sort | while read -r secret; do
  printf "%-55s ✓ encrypted\n" "$secret"
done

if [ -f secrets.nix ]; then
  missing=0
  while read -r expected; do
    if [ ! -f "$expected" ]; then
      if [ "$missing" -eq 0 ]; then
        echo
        echo "declared in secrets.nix but MISSING on disk:"
      fi
      echo "  ✗ $expected"
      missing=$((missing + 1))
    fi
  done < <(grep -o '"[^"]*\.age"' secrets.nix | tr -d '"')
fi

echo
echo "// secrets // passage (interactive / emacs)"
echo
find passage-store -name "*.age" -type f 2>/dev/null | sort | while read -r secret; do
  entry="${secret#passage-store/}"
  entry="${entry%.age}"
  printf "  %s\n" "$entry"
done
