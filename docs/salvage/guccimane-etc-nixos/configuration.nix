{ config, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  nixpkgs.config.allowUnfree = true;

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Desktop Environment (KDE Plasma 6 + Hyprland)
  services.xserver.enable = true;
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.wayland.enable = true;
  services.desktopManager.plasma6.enable = true;
  
  # Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Networking
  networking.firewall.checkReversePath = "loose";
  networking.firewall.allowedTCPPorts = [ 8000 ];
  services.tailscale.enable = true;

  environment.systemPackages = with pkgs; [
    tailscale
    git
    vim
    wget
    curl
  ];

  users.users.justin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "render" "networkmanager" "docker" "input" ];
  };

  # Graphics
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    modesetting.enable = true;
  };

  # Audio (for Hyprland)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Security
  security.polkit.enable = true;
  security.rtkit.enable = true;

  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  system.stateVersion = "24.05";
}
