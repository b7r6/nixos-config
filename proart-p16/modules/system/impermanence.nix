# Impermanence configuration for ProArt P16 - REVIEW ONLY, DO NOT ENABLE YET
# To use this, first test with a boot ISO, then import this module
{ config, lib, pkgs, ... }:

{
  # Commented out until ISO verification is complete
  # imports = [
  #   (builtins.fetchTarball {
  #     url = "https://github.com/nix-community/impermanence/archive/master.tar.gz";
  #     sha256 = "0s749g19zf6kj6y3xv59zl8fv2k0qm3m8lw0qlv16cj0gx2y3zcx";
  #   })
  # ];

  # Configure ephemeral root filesystem
  # This wipes the root filesystem on every boot
  fileSystems."/".options = [ "defaults" "size=8G" "mode=755" ];
  
  # Commands to wipe the root subvolume at boot
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    mkdir -p /mnt
    
    # Mount the btrfs root to /mnt
    mount -o subvol=root /dev/nvme0n1p3 /mnt
    
    # Delete existing subvolumes in root
    btrfs subvolume list -o /mnt/root | cut -f9 -d' ' |
    while read subvolume; do
      echo "Removing subvolume $subvolume"
      btrfs subvolume delete "/mnt/$subvolume"
    done && btrfs subvolume delete /mnt/root
    
    # Create a fresh root subvolume
    btrfs subvolume create /mnt/root
    
    # Unmount
    umount /mnt
  '';

  # Define persistent directories and files
  # These will survive across reboots using bind mounts
  environment.persistence."/persist" = {
    hideMounts = true;  # Hide bind mounts from the user
    directories = [
      # System directories to persist
      "/etc/nixos"
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/docker"
      "/etc/NetworkManager/system-connections"
      
      # ProArt P16 specific
      "/etc/machine-id"
      "/etc/gpu-profile"  # Store GPU profile preferences
    ];
    files = [
      # System files to persist
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
    ];
  };

  # System tuning for persistance
  environment.etc = {
    # Create symlinks for machine-id to ensure consistent state
    "machine-id".source = "/persist/etc/machine-id";
    "ssh/ssh_host_ed25519_key".source = "/persist/etc/ssh/ssh_host_ed25519_key";
    "ssh/ssh_host_ed25519_key.pub".source = "/persist/etc/ssh/ssh_host_ed25519_key.pub";
    "ssh/ssh_host_rsa_key".source = "/persist/etc/ssh/ssh_host_rsa_key";
    "ssh/ssh_host_rsa_key.pub".source = "/persist/etc/ssh/ssh_host_rsa_key.pub";
  };

  # Enable FUSE for user-level bind mounts (required for home persistence)
  programs.fuse.userAllowOther = true;

  # This module creates ISO configuration for testing
  # Uncomment and adjust for your needs
  # isoImage = {
  #   makeEfiBootable = true;
  #   makeUsbBootable = true;
  #   compressImage = true;
  #   volumeID = "NIXOS_PROART";
  #   isoName = "nixos-proart-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.iso";
  # };

  # To enable this configuration:
  # 1. Test with boot ISO first
  # 2. Create the ISO image with both disko and impermanence modules
  # 3. Verify partitioning and impermanence work correctly
  # 4. Uncomment the imports section
  # 5. Import this module in your system configuration
} 