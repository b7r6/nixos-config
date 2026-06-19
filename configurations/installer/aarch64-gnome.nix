# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                        // hyper-modern-nixos // installer/aarch64-gnome
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Full GNOME desktop USB installer for aarch64 systems (DGX Spark / GB10)
#
# Live environment with Calamares installer, browser, and full desktop.
#
{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [ ./base.nix ];

  # ── DGX Spark / GB10 Hardware ──────────────────────────────────────────────

  hardware.dgx-spark.enable = lib.mkDefault true;

  # ── Installer Identity ─────────────────────────────────────────────────────

  networking.hostName = "nixos-aarch64-live";

  system.nixos.tags = [
    "gnome"
    "aarch64"
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
    ┃  // hyper-modern-nixos // aarch64 Installer (GNOME)                      ┃
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

  # ── Specialisation for Standard Kernel ─────────────────────────────────────

  # Select "Standard Kernel" from the boot menu if NVIDIA kernel has issues
  specialisation.standard-kernel = {
    inheritParentConfig = true;
    configuration = {
      hardware.dgx-spark.useNvidiaKernel = lib.mkForce false;
      system.nixos.tags = [
        "gnome"
        "aarch64"
        "standard-kernel"
      ];
    };
  };
}
