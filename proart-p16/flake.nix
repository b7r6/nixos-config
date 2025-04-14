{
  description = "ASUS ProArt P16 NixOS Configuration";

  inputs = {
    # Use the latest unstable channel
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Hyprland and plugins
    hyprland.url = "github:hyprwm/Hyprland";
    hy3 = {
      url = "github:outfoxxed/hy3";
      inputs.hyprland.follows = "hyprland";
    };
  };

  outputs = { self, nixpkgs, hyprland, ... }@inputs: {
    # ISO configuration for testing
    nixosConfigurations.proart-iso = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Use the minimal installation CD as base
        "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        
        # Add our custom configuration
        ({ config, pkgs, ... }: {
          # Allow unfree packages for NVIDIA drivers
          nixpkgs.config.allowUnfree = true;
          
          # ISO-specific configuration
          isoImage = {
            # Set image name and version
            isoName = "proart-p16-test-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.iso";
            
            # Set volume ID for the ISO
            volumeID = "PROART_P16_TEST";
            
            # Add an entry to GRUB to make sure our kernel params are preserved
            makeEfiBootable = true;
            makeUsbBootable = true;
            appendToMenuLabel = " ProArt P16 Test";
          };
          
          # System-wide font configuration
          fonts = {
            enableDefaultPackages = true;
            fontconfig = {
              defaultFonts = {
                monospace = [ "Monospace" ];
                sansSerif = [ "Sans" ];
                serif = [ "Serif" ];
              };
            };
          };
        
          # Enable Hyprland at the system level
          programs.hyprland = {
            enable = true;
            xwayland.enable = true;
            package = hyprland.packages.${pkgs.system}.hyprland;
          };
          
          # Auto-login to the live system for testing
          services.getty.autologinUser = "nixos";
          
          # Ensure our monitor-handler script is available in the live environment
          environment.systemPackages = with pkgs; [
            # Write the monitor-handler script directly in the ISO
            (writeShellScriptBin "monitor-handler" ''
              #!/usr/bin/env bash
              
              # Script to handle monitor configurations and lid switch events
              # This is optimized for ASUS ProArt P16 with 3840x2400 display
              
              # Monitor configuration constants
              LAPTOP_MONITOR="eDP-1"
              LAPTOP_RESOLUTION="3840x2400@60"
              LAPTOP_SCALE="1.5"
              
              # Function to check if the laptop lid is closed
              function is_lid_closed() {
                grep -q closed /proc/acpi/button/lid/*/state
                return $?
              }
              
              # Function to detect connected monitors
              function get_connected_monitors() {
                hyprctl monitors -j | jq -r '.[] | select(.name != "HEADLESS-1") | .name' | sort
              }
              
              # Main function
              case "$1" in
                "configure")
                  echo "Configuring monitors..."
                  # Simple configuration for testing
                  hyprctl keyword monitor ",preferred,auto,1"
                  ;;
                "watch-monitors")
                  echo "Monitor watching started"
                  # Watch for monitor change events
                  socat -u UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | \
                  while read -r line; do
                    if [[ "$line" == monitoradded* ]] || [[ "$line" == monitorremoved* ]]; then
                      echo "Monitor change detected"
                      hyprctl keyword monitor ",preferred,auto,1"
                    fi
                  done
                  ;;
                "lid-state")
                  is_lid_closed && echo "closed" || echo "open"
                  ;;
                *)
                  echo "Usage: $0 [configure|watch-monitors|lid-state]"
                  exit 1
                  ;;
              esac
            '')
            
            # Ensure these tools are available in the ISO
            socat
            jq
            inotify-tools
            brightnessctl
            
            # Add debugging tools
            pciutils
            usbutils
            lshw
            
            # Terminal and basics
            wezterm
            neovim
            git
            hyprland.packages.${pkgs.system}.xdg-desktop-portal-hyprland
          ];
          
          # Create a basic Hyprland config in the test environment
          environment.etc."xdg/hyprland/hyprland.conf".text = ''
            # Auto-detected monitor config
            monitor=,preferred,auto,1
            
            # Environment variables
            env = LIBVA_DRIVER_NAME,radeonsi
            env = WLR_NO_HARDWARE_CURSORS,1
            
            # Basic UI settings
            general {
              gaps_in = 5
              gaps_out = 10
              border_size = 2
              layout = dwindle
            }
            
            # Default keybindings
            bind = SUPER, Return, exec, wezterm
            bind = SUPER, Q, killactive
            bind = SUPER, M, exit
            
            # Launch terminal on startup to show test information
            exec-once = wezterm start -- bash -c "echo 'ProArt P16 Test ISO\nMonitor info:' && sleep 2 && hyprctl monitors"
          '';
          
          # Boot params for the ISO
          boot.kernelParams = [ 
            "quiet" 
            "splash" 
            "button.lid_init_state=open"
          ];
          
          # GPU drivers for the ASUS ProArt P16
          services.xserver.videoDrivers = [ "nvidia" "amdgpu" ];
          
          # NVIDIA driver configuration
          hardware.nvidia = {
            modesetting.enable = true;
            powerManagement.enable = true;
            open = false;
            prime = {
              offload.enable = true;
              amdgpuBusId = "PCI:6:0:0"; 
              nvidiaBusId = "PCI:1:0:0";
            };
          };
          
          # AMD GPU configuration - using updated option names
          hardware.graphics = {
            enable = true;
            extraPackages = with pkgs; [
              mesa
              amdvlk
              vaapiVdpau
              libvdpau-va-gl
            ];
          };
          
          # System state version
          system.stateVersion = "24.05";
        })
      ];
    };
  };
} 