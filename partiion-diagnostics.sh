#!/usr/bin/env bash
# NixOS Disko/Impermanence Diagnostics Script
# This script collects system information needed for NixOS disko/impermanence setup

OUTPUT_FILE="nixos-diagnostics-$(date +%Y%m%d-%H%M%S).txt"

echo "Collecting NixOS system information for disko/impermanence setup..."
echo "Results will be saved to $OUTPUT_FILE"

# Function to print section headers
section() {
  echo -e "\n\n===================================================================" | tee -a "$OUTPUT_FILE"
  echo ">>> $1" | tee -a "$OUTPUT_FILE"
  echo "===================================================================" | tee -a "$OUTPUT_FILE"
}

# Start with a clean file
> "$OUTPUT_FILE"

# Basic system information
section "SYSTEM INFORMATION"
echo "Date: $(date)" | tee -a "$OUTPUT_FILE"
echo "Hostname: $(hostname)" | tee -a "$OUTPUT_FILE"
echo "Kernel: $(uname -r)" | tee -a "$OUTPUT_FILE"
echo "NixOS Version: $(nixos-version 2>/dev/null || echo "Not available")" | tee -a "$OUTPUT_FILE"

# Boot mode
section "BOOT MODE"
if [ -d /sys/firmware/efi ]; then
  echo "UEFI boot mode" | tee -a "$OUTPUT_FILE"
else
  echo "BIOS/Legacy boot mode" | tee -a "$OUTPUT_FILE"
fi

# Disk and partition information
section "DISK AND PARTITION LAYOUT"
echo "lsblk output:" | tee -a "$OUTPUT_FILE"
lsblk -f | tee -a "$OUTPUT_FILE"

echo -e "\nlsblk with more details:" | tee -a "$OUTPUT_FILE"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID,LABEL | tee -a "$OUTPUT_FILE"

section "DISK USAGE"
df -h | tee -a "$OUTPUT_FILE"

# Current mount points
section "CURRENT MOUNT POINTS"
mount | grep -v "tmpfs\|proc\|sys" | tee -a "$OUTPUT_FILE"

# Storage device information
section "STORAGE DEVICE DETAILS"
if command -v smartctl &> /dev/null; then
  for disk in $(lsblk -d -o NAME | grep -v NAME); do
    echo -e "\nSMART info for /dev/$disk:" | tee -a "$OUTPUT_FILE"
    smartctl -i /dev/$disk 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "Failed to get SMART info" | tee -a "$OUTPUT_FILE"
  done
else
  echo "smartctl not available, skipping SMART information" | tee -a "$OUTPUT_FILE"
fi

# Current NixOS configuration
section "NIXOS CONFIGURATION"
if [ -f /etc/nixos/configuration.nix ]; then
  cat /etc/nixos/configuration.nix | tee -a "$OUTPUT_FILE"
else
  echo "configuration.nix not found at standard location" | tee -a "$OUTPUT_FILE"
fi

# Hardware configuration
section "NIXOS HARDWARE CONFIGURATION"
if command -v nixos-generate-config &> /dev/null; then
  nixos-generate-config --show-hardware-config 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "Failed to generate hardware config" | tee -a "$OUTPUT_FILE"
else
  echo "nixos-generate-config not available" | tee -a "$OUTPUT_FILE"
fi

# Check for existing disko configuration
section "EXISTING DISKO CONFIGURATION"
find /etc/nixos -name "*.nix" -exec grep -l "disko" {} \; | while read -r file; do
  echo -e "\nDisko configuration found in $file:" | tee -a "$OUTPUT_FILE"
  cat "$file" | tee -a "$OUTPUT_FILE"
done

# Check for existing impermanence configuration
section "EXISTING IMPERMANENCE CONFIGURATION"
find /etc/nixos -name "*.nix" -exec grep -l "impermanence" {} \; | while read -r file; do
  echo -e "\nImpermanence configuration found in $file:" | tee -a "$OUTPUT_FILE"
  cat "$file" | tee -a "$OUTPUT_FILE"
done

# Check for persisted directories
section "PERSISTED DIRECTORIES"
if [ -d /persist ]; then
  echo "Content of /persist:" | tee -a "$OUTPUT_FILE"
  find /persist -type d -maxdepth 3 2>/dev/null | tee -a "$OUTPUT_FILE"
else
  echo "/persist directory not found" | tee -a "$OUTPUT_FILE"
fi

# User home structure
section "USER HOME STRUCTURE"
echo "Current user: $(whoami)" | tee -a "$OUTPUT_FILE"
echo "Home directory structure:" | tee -a "$OUTPUT_FILE"
ls -la ~ | head -20 | tee -a "$OUTPUT_FILE"

# Flake information if available
section "FLAKE CONFIGURATION"
if [ -f /etc/nixos/flake.nix ]; then
  cat /etc/nixos/flake.nix | tee -a "$OUTPUT_FILE"
else
  find /etc/nixos -name "flake.nix" -exec cat {} \; | tee -a "$OUTPUT_FILE" || echo "No flake.nix found" | tee -a "$OUTPUT_FILE"
fi

# Package information
section "INSTALLED PACKAGES"
nix-env -qa --installed "*" | head -20 | tee -a "$OUTPUT_FILE"
echo "[...truncated for brevity]" | tee -a "$OUTPUT_FILE"

# NixOS generations
section "NIXOS GENERATIONS"
sudo nix-env -p /nix/var/nix/profiles/system --list-generations | head -10 | tee -a "$OUTPUT_FILE"
echo "[...truncated for brevity]" | tee -a "$OUTPUT_FILE"

# User nix profile generations
section "USER NIX PROFILE GENERATIONS"
nix-env --list-generations | head -10 | tee -a "$OUTPUT_FILE"
echo "[...truncated for brevity]" | tee -a "$OUTPUT_FILE"

# Home-manager configuration if available
section "HOME MANAGER CONFIGURATION"
find ~ -name "home.nix" -exec cat {} \; | tee -a "$OUTPUT_FILE" || echo "No home.nix found" | tee -a "$OUTPUT_FILE"

echo -e "\n\nDiagnostic information collection complete. Please check $OUTPUT_FILE"
echo "You can now share this file to get personalized advice on setting up NixOS with disko and impermanence."
