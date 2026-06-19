# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                             // hyper-modern-nixos // common
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Common NixOS configuration shared across all hosts.
#
{ ... }: {
  imports = [
    # Core system
    ./base.nix
    ./nix.nix
    ./packages.nix
    ./greetd.nix
    ./myusers.nix
    ./secrets.nix

    # Hardware
    ./bluetooth.nix
    ./nvidia.nix
    ./radeon.nix
    ./usb.nix

    # Networking
    ./network.nix
    ./network-manager.nix

    # Virtualization & containers
    ./docker.nix
    ./libvirt.nix

    # Services
    ./postgres.nix
    ./backup.nix
    ./attic.nix
    ./nativelink.nix
    ./rclone-mount.nix

    # Development
    ./android.nix
    ./appimage.nix
    ./nix-ld.nix

    # Special
    ./impermanence.nix
    ./impurity.nix
    ./xremap.nix
  ];

  # Network configuration
  hyper-modern-nixos.network = {
    enable = true;
    tailnet.domain = "osiris-walleye.ts.net";
    firewall.enable = false;
    useBackupResolver = true;
  };

  # ── Fleet-wide user model ──────────────────────────────────────────────────
  # Groups + SSH keys are declared ONCE here and apply to every managed user on
  # every host (see modules/nixos/common/myusers.nix). Per-host/per-user extras
  # go in hyper-modern-nixos.users.users.<name>.{extraGroups,authorizedKeys}.
  hyper-modern-nixos.users = {
    defaultAuthorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINbn+XF6n9v9VKLFGLBVz+G1LyL6GlcgZbIwhP89PPsp" # b7r6
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1ptqyz5C3YCcMgh3LUbXtjeS1rIZ5/6RHnH7D93Nqf" # 1password id_ed25519_b7r6
    ];
  };
}
