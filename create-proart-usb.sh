#!/bin/bash
set -e

echo "Building ProArt P16 test ISO with minimal configuration..."

# Build the ISO directly using nixos-generators
nix-shell -p nixos-generators --run "nixos-generate -f iso \
  --flake /home/b7r6/nixos-config#proart-iso \
  --show-trace \
  --option sandbox false"

# Find the ISO
ISO_PATH=$(readlink -f ./result/iso/*.iso)
if [ ! -f "$ISO_PATH" ]; then
  echo "ISO build failed or ISO not found"
  exit 1
fi

echo "ISO created at: $ISO_PATH"

# List available USB drives
echo -e "\nAvailable USB drives:"
lsblk -dpo NAME,SIZE,MODEL | grep -E 'sd[a-z]|nvme[0-9]'

# Get USB drive selection from user
echo -e "\nCAUTION: This will ERASE ALL DATA on the selected drive!"
read -p "Enter the device name for your USB drive (e.g., sda): " DRIVE

if [[ ! $DRIVE =~ ^sd[a-z]$ && ! $DRIVE =~ ^nvme[0-9]n[0-9]$ ]]; then
  echo "Invalid drive format. Exiting for safety."
  exit 1
fi

DRIVE_PATH="/dev/$DRIVE"
echo -e "\nYou selected: $DRIVE with ISO: $ISO_PATH"
echo "ALL DATA WILL BE LOST on $DRIVE_PATH"
read -p "Are you sure? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Operation cancelled."
  exit 0
fi

echo "Writing ISO to $DRIVE_PATH..."
# Try different methods for privilege escalation
if command -v pkexec >/dev/null 2>&1; then
  pkexec dd if="$ISO_PATH" of="$DRIVE_PATH" bs=4M status=progress oflag=sync
elif command -v doas >/dev/null 2>&1; then
  doas dd if="$ISO_PATH" of="$DRIVE_PATH" bs=4M status=progress oflag=sync
else
  echo "Please run this command manually:"
  echo "sudo dd if=\"$ISO_PATH\" of=\"$DRIVE_PATH\" bs=4M status=progress oflag=sync"
  exit 1
fi

echo -e "\nDone! USB drive ready."

echo -e "\nBoot instructions for ProArt P16:"
echo "1. Insert the USB drive and power on the laptop"
echo "2. Press F8 repeatedly during startup (right after power button)"
echo "3. In the boot menu, select the USB drive entry"
echo "4. The system will boot from the test ISO" 