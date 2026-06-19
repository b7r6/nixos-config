# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // base
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Core system settings: SSH, sudo, home-manager integration.
#
{ lib, ... }: {
  # SSH daemon
  services.openssh.enable = true;

  # Use standard ssh-agent (conflicts with gnome-keyring's gcr-ssh-agent)
  # Set low priority so wayland module can override if gnome-keyring is enabled
  programs.ssh.startAgent = lib.mkDefault true;

  # Passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Home-manager integration
  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "hm-backup";

  # Required for xdg portals when using home-manager.useUserPackages
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  # Handy nix helper
  programs.nh.enable = true;
}
