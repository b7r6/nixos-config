# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                        // hyper-modern-nixos // installer/x86_64-minimal
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Minimal CLI USB installer for x86_64 systems
#
# Headless, SSH-accessible, optimized for fast builds and remote installs.
#
{ pkgs, ... }:

{
  imports = [ ./base.nix ];

  # ── Installer Identity ─────────────────────────────────────────────────────

  networking.hostName = "nixos-x86_64-installer";

  system.nixos.tags = [
    "minimal"
    "x86_64"
  ];

  # ── x86_64 Hardware ────────────────────────────────────────────────────────

  # Support both BIOS and UEFI boot
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  # Common x86 hardware support
  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sr_mod"
    "sdhci_pci"
  ];

  boot.kernelModules = [
    "kvm-intel"
    "kvm-amd"
  ];

  # ── Console-focused Environment ────────────────────────────────────────────

  # No GUI - pure CLI
  services.xserver.enable = false;

  # Getty on virtual consoles
  systemd.services."getty@tty1".enable = true;

  # Auto-login on tty1 for immediate access
  services.getty.autologinUser = "nixos";

  # ── Additional CLI Tools ───────────────────────────────────────────────────

  environment.systemPackages = with pkgs; [
    # Network diagnostics
    inetutils
    nmap
    tcpdump
    ethtool

    # System monitoring
    iotop
    sysstat
    strace
    lsof

    # Editors
    neovim
    nano

    # Disko for declarative partitioning
    disko
  ];

  # ── Welcome Message ────────────────────────────────────────────────────────

  environment.etc."motd".text = ''

    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    ┃  // hyper-modern-nixos // x86_64 Installer (Minimal)                     ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃                                                                          ┃
    ┃  User: nixos  Password: nixos                                            ┃
    ┃  SSH is enabled - connect remotely for installation                      ┃
    ┃                                                                          ┃
    ┃  Quick start:                                                            ┃
    ┃    1. Clone your config:  git clone <your-nixos-config>                  ┃
    ┃    2. Partition disks:    sudo disko --mode disko <disko.nix>            ┃
    ┃    3. Install:            sudo nixos-install --flake .#<hostname>        ┃
    ┃                                                                          ┃
    ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

  '';
}
