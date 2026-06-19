# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                        // hyper-modern-nixos // installer/x86_64-gnome
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Full GNOME desktop USB installer for x86_64 systems
#
# Live environment with Calamares installer, browser, and full desktop.
#
{ pkgs, ... }:

{
  imports = [ ./base.nix ];

  # ── Installer Identity ─────────────────────────────────────────────────────

  networking.hostName = "nixos-x86_64-live";

  system.nixos.tags = [
    "gnome"
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

  # ── GNOME Desktop Environment ──────────────────────────────────────────────

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Auto-login for live environment
  services.displayManager.autoLogin = {
    enable = true;
    user = "nixos";
  };

  # ── Audio ──────────────────────────────────────────────────────────────────

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # ── Desktop Applications ───────────────────────────────────────────────────

  environment.systemPackages = with pkgs; [
    # Web browser
    firefox

    # GNOME apps
    gnome-terminal
    nautilus
    gnome-text-editor
    gnome-system-monitor

    # Disk management
    gparted
    gnome-disk-utility

    # NixOS graphical installer
    calamares-nixos

    # Additional utilities
    disko
  ];

  # ── GNOME Tweaks ───────────────────────────────────────────────────────────

  # Exclude some heavy GNOME apps to keep image smaller
  environment.gnome.excludePackages = with pkgs; [
    gnome-music
    gnome-photos
    totem # video player
    epiphany # gnome web browser (we have firefox)
    geary # email client
    gnome-characters
    gnome-contacts
    gnome-maps
    gnome-weather
    simple-scan
  ];

  # ── Welcome Message ────────────────────────────────────────────────────────

  environment.etc."motd".text = ''

    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
    ┃  // hyper-modern-nixos // x86_64 Installer (GNOME)                       ┃
    ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫
    ┃                                                                          ┃
    ┃  User: nixos  Password: nixos                                            ┃
    ┃                                                                          ┃
    ┃  Installation options:                                                   ┃
    ┃    - Calamares: Graphical installer (Activities > Calamares)             ┃
    ┃    - Manual: nixos-install --flake <your-config>#<hostname>              ┃
    ┃                                                                          ┃
    ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

  '';
}
