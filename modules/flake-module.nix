# Top-level flake-module for the system
{ self, lib, flake-parts-lib, ... }:

let
  inherit (flake-parts-lib) mkPerSystemOption;
in
{
  options = {
    perSystem = mkPerSystemOption ({ config, pkgs, system, ... }: {
      # Per-system options can be defined here
    });
  };

  config = {
    # Import all the modules we need
    flake.nixosModules = {
      # System modules
      docker = import ../modules/system/docker.nix;
      disko = import ../modules/system/disko.nix;
      impermanence = import ../modules/system/impermanence.nix;
      refind = import ../modules/system/refind.nix;
      
      # Home-manager modules
      emacs = import ../modules/home/emacs;
      tmux = import ../modules/home/tmux.nix;
      wezterm = import ../modules/home/wezterm.nix;
      firefox = import ../modules/home/firefox.nix;
      vscode = import ../modules/home/vscode.nix;
      cursor = import ../modules/home/cursor.nix;
      hyprland = import ../modules/home/hyprland.nix;
      xremap = import ../modules/home/xremap.nix;
      
      # Make these modules available as a convenience
      default = { imports = [ ../modules/home/emacs ]; };
      emacs-dev = { imports = [ ../modules/home/emacs ]; };
    };
    
    # Per-system configuration
    perSystem = { config, pkgs, system, ... }: {
      # Import the Emacs development module
      imports = [
        ../modules/home/emacs/flake-module.nix
      ];

      # Configure the Emacs development environment
      emacs-dev = {
        enable = true;
        
        # Default packages for Emacs development
        extraEmacsPackages = [
          "company" "magit" "projectile" "counsel" "which-key"
          "doom-themes" "doom-modeline" "all-the-icons" "treemacs"
          "markdown-mode" "yaml-mode" "nix-mode" "direnv" "eglot"
          "org" "org-roam" "expand-region" "multiple-cursors"
          "paredit" "paredit-everywhere" "flycheck" "package-lint"
        ];
        
        # Include password store functionality
        includePassModule = true;
      };
      
      # Make the Emacs development package and shell available
      packages.emacs-development = config.emacs-dev.packages.emacs-development;
      devShells.emacs = config.devShells.emacs;
      
      # Add app outputs for creating ISOs and test drives
      apps = {
        # Create ProArt P16 test ISO
        proart-iso = {
          type = "app";
          program = toString (pkgs.writeShellScript "build-proart-iso" ''
            # Allow broken packages (for ZFS)
            export NIXPKGS_ALLOW_BROKEN=1
            
            # Create a temporary directory for the ISO config
            TEMP_DIR=$(mktemp -d)
            ISO_CONFIG="$TEMP_DIR/iso-config.nix"
            
            # Create the ISO configuration file
            cat > "$ISO_CONFIG" << 'EOF'
            { ... }:
            {
              imports = [
                ${../proart-p16/modules/system/iso.nix}
              ];
              
              # Disable problematic services like ZFS
              boot.supportedFilesystems = lib.mkForce [ "btrfs" "vfat" "ext4" "ntfs" ];
              
              # Use a more conservative kernel
              boot.kernelPackages = pkgs.linuxPackages_latest;
              
              # Enable experimental features for compatibility
              nix.settings.experimental-features = ["nix-command" "flakes"];
            }
            EOF
            
            # Build the ISO image
            echo "Building ProArt P16 test ISO..."
            nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage -I nixos-config="$ISO_CONFIG"
            
            # Copy the ISO to the current directory
            ISO_PATH=$(readlink -f result/iso/*.iso)
            ISO_NAME=$(basename "$ISO_PATH")
            cp "$ISO_PATH" "./$ISO_NAME"
            
            # Clean up
            rm -rf "$TEMP_DIR"
            
            echo "ISO created: ./$ISO_NAME"
            echo
            echo "To write to the USB drive (replace sdX with your device):"
            echo "sudo dd if=./$ISO_NAME of=/dev/sdX bs=4M status=progress conv=fsync"
            echo
            echo "Boot instructions for ProArt P16:"
            echo "1. Power on and press F8 repeatedly to access boot menu"
            echo "2. Select the USB drive from the boot menu"
          '');
        };
        
        # Create a bootable USB drive from the ISO
        write-usb = {
          type = "app";
          program = toString (pkgs.writeShellScript "write-usb" ''
            # Check if we have an ISO file
            ISO_FILES=(*.iso)
            if [ ! -f "''${ISO_FILES[0]}" ]; then
              echo "No ISO file found. Run 'nix run .#proart-iso' first."
              exit 1
            fi
            
            # Find available USB drives
            echo "Available USB drives:"
            lsblk -d -o NAME,SIZE,MODEL,SERIAL | grep -v "^loop" | grep -v "^nvme"
            
            # Ask for the target drive
            echo 
            echo "CAUTION: This will ERASE ALL DATA on the selected drive!"
            echo -n "Enter the device name (e.g., sda): "
            read DEVICE
            
            # Confirm
            echo 
            echo "You selected: $DEVICE"
            echo "ALL DATA WILL BE LOST on /dev/$DEVICE"
            echo -n "Are you sure? (yes/no): "
            read CONFIRM
            
            if [ "$CONFIRM" != "yes" ]; then
              echo "Operation cancelled."
              exit 0
            fi
            
            # Write the ISO to the USB drive
            echo "Writing ISO to /dev/$DEVICE..."
            sudo dd if="''${ISO_FILES[0]}" of="/dev/$DEVICE" bs=4M status=progress conv=fsync
            sudo sync
            
            echo "Done! USB drive ready."
            echo
            echo "Boot instructions for ProArt P16:"
            echo "1. Power on and press F8 repeatedly to access boot menu"
            echo "2. Select the USB drive from the boot menu"
          '');
        };
      };
    };
  };
} 