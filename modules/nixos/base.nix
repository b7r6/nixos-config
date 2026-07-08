# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // base
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Core system settings: SSH, sudo, home-manager integration.
#
{ lib, ... }: {
  # SSH daemon — accept passwords, keys, whatever works. Security comes from
  # the network layer (tailscale, firewalls), not from crippling auth methods.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
    # Store host keys in /persist so they survive impermanence root wipes.
    # On non-impermanence hosts this is harmless (the keys just also exist there).
    hostKeys = [
      { path = "/persist/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
      { path = "/persist/etc/ssh/ssh_host_rsa_key"; type = "rsa"; bits = 4096; }
    ];
  };

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
