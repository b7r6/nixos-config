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
}
