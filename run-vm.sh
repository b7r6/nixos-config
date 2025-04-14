#!/usr/bin/env bash

# Script to build and run a VM for testing ProArt P16 configuration

# Create a temporary directory for the VM
TEMP_DIR=$(mktemp -d)
echo "Creating VM in $TEMP_DIR"

# Path to the NixOS ISO
ISO_PATH="$HOME/latest-nixos-minimal-x86_64-linux.iso"

# Create a disk image for the VM
qemu-img create -f qcow2 $TEMP_DIR/disk.qcow2 20G

# Run QEMU with appropriate settings
qemu-system-x86_64 \
  -enable-kvm \
  -m 4G \
  -smp 4 \
  -cpu host \
  -vga virtio \
  -display gtk,gl=on \
  -drive file=$TEMP_DIR/disk.qcow2,if=virtio \
  -cdrom $ISO_PATH \
  -boot d \
  -device virtio-net,netdev=net0 \
  -netdev user,id=net0 \
  -device virtio-tablet \
  -device virtio-keyboard \
  -usb \
  -device virtio-gpu-gl \
  -device intel-hda \
  -device hda-duplex

echo "VM shutdown. Cleaning up..."
rm -rf $TEMP_DIR 