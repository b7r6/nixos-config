# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hyper-modern-nixos // installer/base
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Base configuration for USB installer images (aarch64 / DGX Spark)
#
# Critical ARM64/GB10 boot requirements:
#   - sbsa_gwdt must load FIRST to disarm the watchdog timer
#   - xhci_plat_hcd for platform USB 3.0 controllers
#   - GRUB with efiInstallAsRemovable for portable boot
#
{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ── Initial Ramdisk ────────────────────────────────────────────────────────

  boot.initrd.systemd.enable = true;

  # Critical kernel modules for ARM64 USB boot
  boot.initrd.kernelModules = [
    # SBSA Generic Watchdog Timer - MUST load first to disarm watchdog
    # Without this, the ARM SBSA watchdog fires and resets the system
    "sbsa_gwdt"

    # USB controllers (critical for ARM64 USB boot)
    "xhci_plat_hcd" # Platform USB 3.0 controllers for ARM64 systems

    # USB storage and modern USB support (for boot device access)
    "uas" # USB Attached SCSI protocol for modern USB drives
    "usb_storage" # USB mass storage

    # USB input devices (essential for emergency mode keyboard access)
    "usbhid" # USB Human Interface Device driver
    "hid" # HID core
    "hid_generic" # Generic HID support

    # Storage access
    "sd_mod" # SCSI disk support
    "nvme" # NVMe SSD support
  ];

  # ── Filesystem Support ─────────────────────────────────────────────────────

  boot.supportedFilesystems = [
    "vfat"
    "ext4"
    "btrfs"
    "ntfs"
    "iso9660"
  ];

  # ── Bootloader ─────────────────────────────────────────────────────────────

  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true; # Critical for portable USB boot
  };

  # ── Networking ─────────────────────────────────────────────────────────────

  networking.hostName = lib.mkDefault "nixos-installer";
  networking.networkmanager.enable = true;

  # ── Time ───────────────────────────────────────────────────────────────────

  time.timeZone = lib.mkDefault "UTC";

  # ── Users ──────────────────────────────────────────────────────────────────

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
    initialPassword = "nixos";
    description = "NixOS Installer";
  };

  # Enable root for emergency mode
  users.users.root.initialHashedPassword = null;

  # Passwordless sudo for installer user
  security.sudo.wheelNeedsPassword = false;

  # ── SSH ────────────────────────────────────────────────────────────────────

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes"; # Allow root for initial setup
      PasswordAuthentication = true;
    };
  };

  # ── Nix Settings ───────────────────────────────────────────────────────────

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };

  # ── Performance ────────────────────────────────────────────────────────────

  zramSwap.enable = true;

  # ── Base Packages ──────────────────────────────────────────────────────────

  environment.systemPackages = with pkgs; [
    # Essential tools
    vim
    wget
    curl
    git
    htop
    btop

    # Hardware inspection
    lshw
    pciutils
    usbutils
    nvme-cli

    # Disk tools
    parted
    gptfdisk
    cryptsetup

    # NixOS installation
    nixos-install-tools

    # Utilities
    rsync
    tree
    file
    unzip
    zip
    tmux
  ];

  # ── State Version ──────────────────────────────────────────────────────────

  system.stateVersion = "25.11";
}
