#!/usr/bin/env bash
# Script to test ProArt P16 configuration in QEMU

set -euo pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="${SCRIPT_DIR}"
ISO_DIR="${VM_DIR}/iso"
DISK_DIR="${VM_DIR}/disks"

# Create necessary directories
mkdir -p "${ISO_DIR}" "${DISK_DIR}"

# VM settings
VM_NAME="proart-test"
DISK_IMG="${DISK_DIR}/${VM_NAME}.qcow2"
DISK_SIZE="20G"
RAM_SIZE="4G"
CPU_CORES="4"
DISPLAY_RES="3840x2400" # ProArt P16 native resolution

# Check if the disk image exists
if [ ! -f "${DISK_IMG}" ]; then
    echo "Creating disk image ${DISK_IMG}..."
    qemu-img create -f qcow2 "${DISK_IMG}" "${DISK_SIZE}"
fi

# Check if we have a NixOS ISO
NIXOS_ISO="${ISO_DIR}/nixos-latest.iso"
if [ ! -f "${NIXOS_ISO}" ]; then
    echo "Downloading latest NixOS ISO..."
    curl -L https://channels.nixos.org/nixos-unstable/latest-nixos-minimal-x86_64-linux.iso -o "${NIXOS_ISO}"
fi

# QEMU acceleration options based on available hardware
KVM_ARGS=""
if [ -e /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "Using KVM acceleration"
    KVM_ARGS="-enable-kvm -cpu host"
fi

# Run the VM with high-DPI settings
echo "Starting VM with display resolution ${DISPLAY_RES}..."
qemu-system-x86_64 \
    -name "${VM_NAME}" \
    ${KVM_ARGS} \
    -smp "${CPU_CORES}" \
    -m "${RAM_SIZE}" \
    -drive file="${DISK_IMG}",format=qcow2 \
    -cdrom "${NIXOS_ISO}" \
    -boot d \
    -device virtio-vga-gl \
    -display gtk,gl=on,zoom-to-fit=on \
    -device qemu-xhci \
    -device usb-tablet \
    -device intel-hda \
    -device hda-duplex \
    -device e1000,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-balloon \
    -vga virtio \
    -device qemu-xhci,id=xhci \
    -device usb-kbd,bus=xhci.0 \
    -device usb-mouse,bus=xhci.0 \
    -device virtio-rng-pci 