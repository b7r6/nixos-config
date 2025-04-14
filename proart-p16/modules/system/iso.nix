# ISO configuration for testing disko and impermanence on the ProArt P16
{ config, lib, pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
    # Uncomment these to test them in the ISO
    # ./disko.nix
    # ./impermanence.nix
    # ./refind.nix
  ];

  # ISO-specific configuration
  isoImage = {
    # Make the ISO bootable on UEFI systems
    makeEfiBootable = true;
    
    # Make the ISO bootable on legacy BIOS systems
    makeUsbBootable = true;
    
    # Compress the ISO to reduce size
    compressImage = true;
    
    # Set ISO volume ID
    volumeID = "NIXOS_PROART_TEST";
    
    # Set the ISO name
    isoName = "nixos-proart-test-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.iso";
    
    # Include additional packages in the ISO
    contents = [
      { source = ./README.md; target = "README.md"; }
    ];
  };

  # Enable networking in the live environment
  networking = {
    wireless.enable = false; # Use NetworkManager instead
    networkmanager.enable = true;
    
    # Configure DHCP
    useDHCP = false;
    interfaces.enp0s31f6.useDHCP = true;
    interfaces.wlp1s0.useDHCP = true;
  };

  # Enable SSH server for remote debugging if needed
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Set a password for the root user in the live system
  users.users.root.initialPassword = "nixos";

  # Include testing tools
  environment.systemPackages = with pkgs; [
    # Disk utilities
    parted
    gparted
    btrfs-progs
    ntfs3g
    e2fsprogs
    exfatprogs
    
    # System tools
    pciutils
    usbutils
    lshw
    inxi
    lsof
    htop
    btop
    
    # Networking tools
    inetutils
    curl
    wget
    iperf
    
    # Development tools
    git
    vim
    neovim
    
    # Hardware test tools
    smartmontools
    memtest86plus
    lm_sensors
    powertop
    
    # GPU testing tools
    glxinfo
    vulkan-tools
    vdpauinfo
    radeontop
    
    # Backup tools
    rsync
    grsync
    restic
    
    # Misc utilities
    tmux
    ripgrep
    fd
    jq
    tree
    
    # Add a script to help testing disk setup
    (writeShellScriptBin "test-disko" ''
      #!/usr/bin/env bash
      
      # Display help message
      function show_help {
        echo "Usage: test-disko [options]"
        echo "Options:"
        echo "  -h, --help              Show this help message"
        echo "  -d, --dry-run           Perform a dry run (don't actually format)"
        echo "  -f, --force             Force formatting without confirmation"
        echo "  -v, --verbose           Show detailed output"
        echo "  -t, --target DEV        Set target device (default: /dev/nvme0n1)"
        echo ""
        echo "This script helps test the disko configuration for the ProArt P16."
        echo "It will format the target disk according to the disko configuration."
        echo "USE WITH CAUTION - THIS WILL ERASE ALL DATA ON THE TARGET DISK."
      }
      
      # Default values
      DRY_RUN=0
      FORCE=0
      VERBOSE=0
      TARGET_DEVICE="/dev/nvme0n1"
      
      # Parse command line arguments
      while [[ $# -gt 0 ]]; do
        case $1 in
          -h|--help)
            show_help
            exit 0
            ;;
          -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
          -f|--force)
            FORCE=1
            shift
            ;;
          -v|--verbose)
            VERBOSE=1
            shift
            ;;
          -t|--target)
            TARGET_DEVICE="$2"
            shift 2
            ;;
          *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
        esac
      done
      
      # Confirm formatting
      if [[ $FORCE -eq 0 ]]; then
        echo "WARNING: This will erase all data on $TARGET_DEVICE"
        echo "Press Ctrl+C now to abort, or Enter to continue..."
        read
      fi
      
      # Create a temporary directory to hold the disko configuration
      TEMP_DIR=$(mktemp -d)
      
      # Write disko configuration to temporary file
      cat > "$TEMP_DIR/disko-config.nix" << 'EOF'
      { disks ? [ "/dev/nvme0n1" ], ... }:
      {
        disko.devices = {
          disk = {
            nvme0 = {
              type = "disk";
              device = builtins.elemAt disks 0;
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
                        "/root" = {
                          mountpoint = "/";
                          mountOptions = ["subvol=root" "compress=zstd" "noatime"];
                        };
                        "/nix" = {
                          mountpoint = "/nix";
                          mountOptions = ["subvol=nix" "compress=zstd" "noatime"];
                        };
                        "/persist" = {
                          mountpoint = "/persist";
                          mountOptions = ["subvol=persist" "compress=zstd" "noatime"];
                        };
                        "/home" = {
                          mountpoint = "/home";
                          mountOptions = ["subvol=home" "compress=zstd" "noatime"];
                        };
                        "/snapshots" = {};
                      };
                    };
                  };
                };
              };
            };
          };
        };
      }
      EOF
      
      # Run disko formatting
      if [[ $DRY_RUN -eq 1 ]]; then
        OPTS="--dry-run"
        echo "Performing DRY RUN - no changes will be made"
      else
        OPTS=""
      fi
      
      if [[ $VERBOSE -eq 1 ]]; then
        OPTS="$OPTS --verbose"
      fi
      
      echo "Running disko with target device: $TARGET_DEVICE"
      disko $OPTS --mode format --flake "$TEMP_DIR/disko-config.nix#disks=[\"$TARGET_DEVICE\"]"
      
      # Cleanup
      rm -rf "$TEMP_DIR"
      
      echo "Done!"
    '')
  ];

  # Enable hardware acceleration (updated to remove deprecated option)
  hardware.opengl = {
    enable = true;
    # driSupport = true; # Removed deprecated option
    driSupport32Bit = true;
  };

  # Enable hybrid graphics support
  services.xserver.videoDrivers = [ "amdgpu" "nvidia" ];
  
  # NVIDIA configuration
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    
    # Optimus/Prime setup
    prime = {
      offload.enable = true;
      # These values need to be verified with `lspci` in the actual system
      amdgpuBusId = "PCI:6:0:0"; # AMD Radeon 890M
      nvidiaBusId = "PCI:1:0:0"; # NVIDIA RTX 4060
    };
  };

  # Customize the ISO installer boot parameters
  boot = {
    kernelParams = [
      "boot.shell_on_fail"
      "console=tty1"
      "console=ttyS0,115200n8"
    ];
    
    # Add kernel modules for hardware support
    initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "ahci"
      "usbhid"
      "usb_storage"
      "sd_mod"
      "amdgpu"
    ];
    
    # Better support for newer hardware
    kernelPackages = pkgs.linuxPackages_latest;
  };

  # Set hostname for the live system
  networking.hostName = "proart-test";

  # System configuration
  system.stateVersion = "24.05";
} 