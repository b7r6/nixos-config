# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                        // hyper-modern-nixos // installer/x86_64-gnome
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Full GNOME desktop USB installer for x86_64 systems
#
# Live environment with Calamares installer, browser, and full desktop.
#
{ pkgs, lib, ... }:

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

  # Common x86 hardware support (base.nix now gates the ARM-only initrd modules
  # by arch, so no override is needed here — and mkForce [] would wipe the ISO
  # image module's loop/overlay and make the stick non-booting).
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

  # Exclude some heavy GNOME apps to keep image smaller. Resolved by NAME and
  # filtered, so an app removed upstream (e.g. gnome-photos, archived) is simply
  # skipped instead of throwing during eval.
  environment.gnome.excludePackages =
    let
      names = [
        "gnome-music"
        "gnome-photos"
        "totem" # video player
        "epiphany" # gnome web browser (we have firefox)
        "geary" # email client
        "gnome-characters"
        "gnome-contacts"
        "gnome-maps"
        "gnome-weather"
        "simple-scan"
      ];
      # tryEval (not `or null`): removed attrs still EXIST but their value is a
      # `throw`, so only tryEval can skip them.
      resolve = n: let r = builtins.tryEval (pkgs.${n} or null); in if r.success then r.value else null;
    in
    builtins.filter (p: p != null) (map resolve names);

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
