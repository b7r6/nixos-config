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
{ pkgs, lib, ... }:

{
  # ── Initial Ramdisk ────────────────────────────────────────────────────────

  boot.initrd.systemd.enable = true;

  # Initrd modules for USB boot. Generic (all-arch) set below; the ARM-only
  # modules are gated by platform — they do NOT exist in the x86_64 kernel, so
  # adding them unconditionally made `modules-shrunk` FATAL on x86 (and the only
  # safe-looking "fix", mkForce [], wiped the ISO image module's own loop/overlay
  # entries and produced a non-booting stick). MERGES with the iso-image module's
  # loop/overlay/squashfs — do not mkForce this.
  boot.initrd.kernelModules =
    [
      # USB storage + modern USB (boot device access)
      "uas" # USB Attached SCSI
      "usb_storage" # USB mass storage
      # USB input (emergency-mode keyboard)
      "usbhid"
      "hid"
      "hid_generic"
      # Storage
      "sd_mod" # SCSI disk
      "nvme" # NVMe SSD
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isAarch64 [
      # SBSA Generic Watchdog Timer — MUST load first to disarm the ARM SBSA
      # watchdog (else it fires and resets). ARM64/DGX only.
      "sbsa_gwdt"
      # Platform USB 3.0 controllers for ARM64.
      "xhci_plat_hcd"
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
