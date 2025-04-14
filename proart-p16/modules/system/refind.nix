# rEFInd bootloader configuration for ProArt P16
{ config, lib, pkgs, ... }:

{
  options.boot.refind-proart = {
    enable = lib.mkEnableOption "Enable rEFInd bootloader with ProArt P16 optimizations";
    
    useGraphics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use graphical boot menu";
    };
    
    resolution = lib.mkOption {
      type = lib.types.str;
      default = "3840 2160"; # 4K resolution for ProArt P16
      description = "Screen resolution for boot menu";
    };
    
    timeout = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Boot menu timeout in seconds";
    };
    
    themeName = lib.mkOption {
      type = lib.types.enum [ "regular" "minimal" "ursamajor" "nord" ];
      default = "regular";
      description = "Theme to use for rEFInd";
    };
  };

  config = lib.mkIf config.boot.refind-proart.enable {
    # Disable systemd-boot
    boot.loader.systemd-boot.enable = false;
    
    # Configure EFI
    boot.loader.efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    
    # Configure rEFInd
    boot.loader.refind = {
      enable = true;
      
      # Don't use systemd for booting
      useSystemd = false;
      
      # Basic configuration
      configurationLimit = 10;
      
      # Extra configuration
      extraConfig = ''
        # Screen resolution
        resolution ${config.boot.refind-proart.resolution}
        
        # Use graphics for boot menu
        ${lib.optionalString config.boot.refind-proart.useGraphics "use_graphics_for linux"}
        
        # Manual scanning to speed up boot
        scanfor manual
        
        # Boot timeout
        timeout ${toString config.boot.refind-proart.timeout}
        
        # Hide boot message
        hideui banner
        
        # Adjust font size for HiDPI
        font_size 24
        
        # Banner customization
        banner_scale fillscreen
        
        # Mouse/touch support
        enable_mouse
        enable_touch
        mouse_size 48
        
        # ProArt P16 specific options
        write_systemd_vars true
        
        # Enable OC/UC profiles via EFI variables
        showtools shell, memtest, gdisk, firmware, bootorder
      '';
      
      # Define custom boot entries
      extraEntries = {
        "NixOS Default" = {
          loader = "\\EFI\\nixos\\bzImage.efi";
          devicetree = "\\EFI\\nixos\\dtbs";
          initrd = "\\EFI\\nixos\\initrd.efi";
          options = "quiet loglevel=3 systemd.show_status=false rd.udev.log_level=3";
        };
        
        "NixOS Console" = {
          loader = "\\EFI\\nixos\\bzImage.efi";
          devicetree = "\\EFI\\nixos\\dtbs";
          initrd = "\\EFI\\nixos\\initrd.efi";
          options = "single";
        };
      };
      
      # Theme selection
      theme = let
        themes = {
          regular = pkgs.fetchFromGitHub {
            owner = "bobafetthotmail";
            repo = "refind-theme-regular";
            rev = "0.13.3";
            sha256 = "1p7m7w5qd2h2zy19s7q5j4dh9rpqnp12pcqaplmb33n4rvh5nwx4";
          };
          
          minimal = pkgs.fetchFromGitHub {
            owner = "EvanPurkhiser";
            repo = "rEFInd-minimal";
            rev = "master";
            sha256 = "1b3bzai4mdgz7lkr2bn9qdlk0h8vwf6q3gpw0k3qzj9r45akavdf";
          };
          
          ursamajor = pkgs.fetchFromGitHub {
            owner = "octomachine";
            repo = "refind-theme-ursamajor";
            rev = "v1.4";
            sha256 = "095nhgnlhkyysqvr9mqgmdrvnnkd3y1yryjsjfs4mkg74fgw4b05";
          };
          
          nord = pkgs.fetchFromGitHub {
            owner = "xLasercut";
            repo = "nord-refind";
            rev = "1.0.0";
            sha256 = "0vw2jcxqpbhgwz87i3xkx87ygszw9nwqbvxrqfx8x14wxm1z5vpl";
          };
        };
      in
        themes.${config.boot.refind-proart.themeName};
    };
    
    # Make sure the EFI system partition is properly configured
    fileSystems."/boot" = lib.mkIf (config.fileSystems ? "/boot") {
      fsType = "vfat";
      options = [ "defaults" "noatime" ];
    };
    
    # Install tools for managing the EFI
    environment.systemPackages = with pkgs; [
      efibootmgr
      efivar
      refind
      sbsigntool  # For secure boot signing
      gptfdisk    # For disk management
      
      # Add script to rebuild the boot entries
      (writeShellScriptBin "refind-rebuild" ''
        #!/usr/bin/env bash
        
        echo "Rebuilding rEFInd configuration..."
        sudo refind-install --usedefault /dev/disk/by-partlabel/ESP --alldrivers
        
        echo "Updating boot entries..."
        sudo efibootmgr -c -d /dev/nvme0n1 -p 1 -L "rEFInd Boot Manager" -l "\\EFI\\refind\\refind_x64.efi"
        
        echo "Done! rEFInd configuration has been updated."
      '')
    ];
  };
} 