# NixOS VM configuration for testing ProArt P16 setup
{ pkgs ? import <nixpkgs> {}, ... }:

let
  # Import the hardware configuration
  hardwareConfig = import ./proart-p16/configuration/hardware-configuration.nix;
  systemConfig = import ./proart-p16/configuration/system.nix;
in
{
  imports = [
    "${pkgs.path}/nixos/modules/virtualisation/qemu-vm.nix"
  ];

  # Basic VM settings
  virtualisation = {
    memorySize = 4096; # 4GB RAM
    cores = 4;         # 4 CPU cores
    graphics = true;   # Enable graphical output
    resolution = { x = 1920; y = 1080; };
  };

  # Include specific configuration from ProArt setup
  environment.systemPackages = with pkgs; [
    wezterm
    alacritty
    firefox
    hyprland
  ];

  # Enable Wayland/Hyprland
  programs.hyprland.enable = true;

  # Set user
  users.users.b7r6 = {
    isNormalUser = true;
    description = "b7r6";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
    initialPassword = "password";
  };

  # Auto-login for testing
  services.xserver.displayManager.autoLogin = {
    enable = true;
    user = "b7r6";
  };

  # Force simple graphics for VM
  hardware.opengl.enable = true;

  # System version
  system.stateVersion = "25.05";
} 