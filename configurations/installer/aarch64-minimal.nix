# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                        // hyper-modern-nixos // installer/aarch64-minimal
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Minimal CLI USB installer for aarch64 systems (DGX Spark / GB10)
#
# Headless, SSH-accessible, optimized for fast builds and remote installs.
#
{ pkgs, lib, ... }:

{
  imports = [ ./base.nix ];

  # ── DGX Spark / GB10 Hardware ──────────────────────────────────────────────

  hardware.dgx-spark.enable = lib.mkDefault true;

  # ── Installer Identity ─────────────────────────────────────────────────────

  networking.hostName = "nixos-aarch64-installer";

  system.nixos.tags = [
    "minimal"
    "aarch64"
  ];

  # ── Console-focused Environment ────────────────────────────────────────────

  # No GUI - pure CLI
  services.xserver.enable = false;

  # Getty on serial and virtual consoles
  systemd.services."getty@tty1".enable = true;
  systemd.services."serial-getty@ttyAMA0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
  };

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
    ┃  // hyper-modern-nixos // aarch64 Installer (Minimal)                    ┃
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
