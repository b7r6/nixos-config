# Disko configuration for ProArt P16 - REVIEW ONLY, DO NOT ENABLE YET
# To use this, first test with a boot ISO, then import this module
{ config, lib, pkgs, ... }:

{
  # Commented out until ISO verification is complete
  # imports = [ 
  #   (builtins.fetchTarball {
  #     url = "https://github.com/nix-community/disko/archive/master.tar.gz";
  #     sha256 = "0qxysfx0w7qnwcgr5jd5qjmgr1a4xp7sb3ahlbs47pdbkbr290kc";
  #   })
  # ];

  # This is a DRAFT configuration - adjust device paths and sizes as needed
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = "/dev/nvme0n1"; # Primary NVMe drive - VERIFY THIS PATH
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00"; # EFI System Partition
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "defaults" ];
              };
            };
            swap = {
              size = "32G"; # Adjust based on RAM size
              type = "8200"; # Linux swap
              content = {
                type = "swap";
                resumeDevice = true; # Enable hibernate support
              };
            };
            root = {
              size = "100%"; # Use rest of the disk
              content = {
                type = "btrfs";
                extraArgs = ["-f"]; # Force formatting
                subvolumes = {
                  # Subvolume for root filesystem (ephemeral)
                  "/root" = {
                    mountpoint = "/";
                    mountOptions = ["subvol=root" "compress=zstd" "noatime"];
                  };
                  # Subvolume for Nix store (persist across reboots)
                  "/nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["subvol=nix" "compress=zstd" "noatime"];
                  };
                  # Subvolume for persistent data
                  "/persist" = {
                    mountpoint = "/persist";
                    mountOptions = ["subvol=persist" "compress=zstd" "noatime"];
                  };
                  # Subvolume for home directory
                  "/home" = {
                    mountpoint = "/home";
                    mountOptions = ["subvol=home" "compress=zstd" "noatime"];
                  };
                  # Snapshot volume for backups and rollbacks
                  "/snapshots" = {
                    mountpoint = "/snapshots";
                    mountOptions = ["subvol=snapshots" "compress=zstd" "noatime"];
                  };
                  # Log volume for system logs
                  "/var-log" = {
                    mountpoint = "/var/log";
                    mountOptions = ["subvol=var-log" "compress=zstd" "noatime"];
                  };
                };
              };
            };
          };
        };
      };
    };
  };

  # Optional: Configure automatic snapshots and cleanup
  # services.snapper = {
  #   configs = {
  #     home = {
  #       subvolume = "/home";
  #       extraConfig = ''
  #         ALLOW_USERS=b7r6
  #         TIMELINE_CREATE=yes
  #         TIMELINE_CLEANUP=yes
  #       '';
  #     };
  #     root = {
  #       subvolume = "/";
  #       extraConfig = ''
  #         TIMELINE_CREATE=yes
  #         TIMELINE_CLEANUP=yes
  #       '';
  #     };
  #   };
  # };

  # To enable this configuration:
  # 1. Test with boot ISO first
  # 2. Verify device paths (nvme0n1)
  # 3. Adjust partition sizes as needed
  # 4. Uncomment the imports section
  # 5. Import this module in your system configuration
} 