# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // filament
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# NVIDIA Jetson AGX Thor Developer Kit (T5000) — a deliberately boring JetPack
# box. NOT on the fleet module stack (self.nixosModules.default): no fleet
# users, no agenix secrets, no tailscale/nativelink/greetd/home-manager. Just
# the platform (jetson-thor), a disk, LAN networking, and ONE local login
# named after the box. The netboot/kexec re-image kit still lives in
# modules/flake/netboot.nix + docs/src/operations/netboot-jetson.md.
#
{ ... }:
{
  networking.hostName = "filament";

  hardware.jetson-thor.enable = true;

  # Hardware-specific kernel modules
  boot.initrd.availableKernelModules = [ "nvme" ];

  # devkit wifi (rtl8852ce) / bluetooth firmware blobs
  hardware.enableRedistributableFirmware = true;

  # LAN over DHCP, NetworkManager as the devkit shipped. No tailscale — reach
  # the box on its LAN address.
  networking.networkmanager.enable = true;
  networking.firewall.enable = false;

  # The whole point: one non-root login named after the box, password to
  # match. No fleet identity, no ssh keys, no secrets. root carries the same
  # password for console/emergency use (SSH stays key-only for root via the
  # default prohibit-password).
  users.mutableUsers = false;
  users.users.filament = {
    isNormalUser = true;
    password = "filament";
    extraGroups = [ "wheel" ];
  };
  users.users.root.password = "filament";

  # passwordless sudo so remote rebuilds don't need an interactive password
  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;

  # Password SSH is the box's only credential (filament / filament).
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  # Flakes, so the box can rebuild itself.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Matches the deployed system (installed as 25.11-era; do not bump on paper)
  system.stateVersion = "25.11";
}
