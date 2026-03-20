#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                        // hyper-modern-nixos // build-usb
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Build and optionally flash USB installer images for aarch64 or x86_64.
#
# Usage:
#   build-usb aarch64-minimal              Build minimal CLI installer for aarch64
#   build-usb x86_64-gnome                 Build GNOME installer for x86_64
#   build-usb aarch64-minimal /dev/sdX     Build and flash to device
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

usage() {
  cat <<EOF
Usage: $(basename "$0") <variant> [device]

Variants:
  aarch64-minimal    Headless CLI installer for ARM64 (DGX Spark, etc.)
  aarch64-gnome      GNOME desktop installer for ARM64
  x86_64-minimal     Headless CLI installer for x86_64
  x86_64-gnome       GNOME desktop installer for x86_64

Options:
  device     Block device to flash (e.g., /dev/sda)
             WARNING: This will ERASE the device!

Examples:
  $(basename "$0") aarch64-minimal              # Build only
  $(basename "$0") x86_64-gnome /dev/sda        # Build and flash

Note: Building for a different architecture requires either:
  - Native hardware, or
  - binfmt emulation (boot.binfmt.emulatedSystems)

EOF
  exit 1
}

log() {
  echo -e "${BLUE}==>${NC} $*"
}

warn() {
  echo -e "${YELLOW}warning:${NC} $*"
}

error() {
  echo -e "${RED}error:${NC} $*" >&2
  exit 1
}

success() {
  echo -e "${GREEN}==>${NC} $*"
}

info() {
  echo -e "${CYAN}::${NC} $*"
}

# ── Argument Parsing ─────────────────────────────────────────────────────────

[[ $# -lt 1 ]] && usage

VARIANT="$1"
DEVICE="${2:-}"

case "$VARIANT" in
  aarch64-minimal)
    PACKAGE="usb-aarch64-minimal"
    ARCH="aarch64"
    ;;
  aarch64-gnome)
    PACKAGE="usb-aarch64-gnome"
    ARCH="aarch64"
    ;;
  x86_64-minimal)
    PACKAGE="usb-x86_64-minimal"
    ARCH="x86_64"
    ;;
  x86_64-gnome)
    PACKAGE="usb-x86_64-gnome"
    ARCH="x86_64"
    ;;
  *)
    error "Unknown variant: $VARIANT"
    ;;
esac

# ── Architecture Check ───────────────────────────────────────────────────────

HOST_ARCH=$(uname -m)
if [[ "$HOST_ARCH" != "$ARCH" ]]; then
  info "Cross-building for $ARCH on $HOST_ARCH"
  if [[ ! -f "/proc/sys/fs/binfmt_misc/qemu-$ARCH" ]] && [[ "$ARCH" == "aarch64" ]]; then
    warn "binfmt emulation may not be configured for $ARCH"
    warn "If build fails, enable: boot.binfmt.emulatedSystems = [\"aarch64-linux\"];"
  fi
fi

# ── Build ────────────────────────────────────────────────────────────────────

log "Building $PACKAGE..."
cd "$FLAKE_DIR"

nix build ".#$PACKAGE" --print-build-logs

ISO_PATH=$(find result/iso -name '*.iso' -type f 2>/dev/null | head -1)

if [[ -z "$ISO_PATH" ]]; then
  error "No ISO found in result/iso/"
fi

ISO_SIZE=$(du -h "$ISO_PATH" | cut -f1)
success "Built: $ISO_PATH ($ISO_SIZE)"

# ── Flash (optional) ─────────────────────────────────────────────────────────

if [[ -n "$DEVICE" ]]; then
  # Validate device
  if [[ ! -b "$DEVICE" ]]; then
    error "$DEVICE is not a block device"
  fi

  # Safety check - don't flash to mounted devices
  if mount | grep -q "^$DEVICE"; then
    error "$DEVICE appears to be mounted. Unmount first."
  fi

  # Extra safety for NVMe/system drives
  if [[ "$DEVICE" == /dev/nvme* ]] || [[ "$DEVICE" == /dev/sda && -d /sys/firmware/efi ]]; then
    warn "This looks like it might be a system drive!"
  fi

  echo ""
  echo -e "${RED}WARNING: This will ERASE all data on $DEVICE${NC}"
  echo ""
  lsblk "$DEVICE" 2>/dev/null || true
  echo ""
  read -p "Type 'yes' to continue: " CONFIRM

  if [[ "$CONFIRM" != "yes" ]]; then
    log "Aborted."
    exit 0
  fi

  log "Flashing to $DEVICE..."
  sudo dd if="$ISO_PATH" of="$DEVICE" bs=4M status=progress conv=fsync

  sync
  success "Done! You can now boot from $DEVICE"
else
  echo ""
  log "To flash to a USB drive:"
  echo "  sudo dd if=$ISO_PATH of=/dev/sdX bs=4M status=progress"
  echo ""
fi
