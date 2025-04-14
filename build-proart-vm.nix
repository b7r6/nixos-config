# Build a VM for the ProArt P16 configuration
let
  nixpkgs = import <nixpkgs> {};
  
  # Create a simplified system configuration
  vmConfig = { config, pkgs, lib, ... }: {
    imports = [
      "${nixpkgs.path}/nixos/modules/virtualisation/qemu-vm.nix"
    ];
    
    # VM settings
    virtualisation = {
      memorySize = 4096;
      cores = 4;
      graphics = true;
      resolution = { x = 1920; y = 1080; };
    };
    
    # Basic system configuration
    environment.systemPackages = with pkgs; [
      wezterm
      firefox
      hyprland
    ];
    
    # Enable Wayland/Hyprland
    programs.hyprland.enable = true;
    
    # Required for Hyprland 
    hardware.opengl.enable = true;
    
    # Add user
    users.users.b7r6 = {
      isNormalUser = true;
      description = "Test User";
      extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
      initialPassword = "password";
    };
    
    # Auto-login
    services.getty.autologinUser = "b7r6";
    
    # Start Hyprland automatically
    system.activationScripts.setupAutostart = ''
      mkdir -p /home/b7r6/.config/autostart
      cat > /home/b7r6/.config/autostart/hyprland.desktop << EOF
      [Desktop Entry]
      Type=Application
      Name=Hyprland
      Exec=Hyprland
      EOF
      chown -R b7r6:users /home/b7r6/.config
    '';
    
    # Allow unfree packages
    nixpkgs.config.allowUnfree = true;
    
    # System version
    system.stateVersion = "23.11";
  };
  
  # Build the VM
  system = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ vmConfig ];
  };
  
in system.config.system.build.vm 