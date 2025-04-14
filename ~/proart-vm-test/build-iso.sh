#!/usr/bin/env bash
# Script to build a custom NixOS ISO for ProArt testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/configuration.nix"
OUTPUT_DIR="${SCRIPT_DIR}/iso"
OUTPUT_ISO="${OUTPUT_DIR}/proart-test.iso"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

echo "Building custom NixOS ISO..."
echo "Using configuration: ${CONFIG_FILE}"
echo "Output will be saved to: ${OUTPUT_ISO}"

# Build the custom ISO
nix-build '<nixpkgs/nixos>' \
  -A config.system.build.isoImage \
  -I nixos-config="${CONFIG_FILE}" \
  --out-link "${OUTPUT_ISO}"

echo "ISO build complete!"
echo "ISO available at: ${OUTPUT_ISO}"
echo "You can now run: ./run-vm.sh" 