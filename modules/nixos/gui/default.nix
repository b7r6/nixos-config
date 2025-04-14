# GUI module for NixOS
{ pkgs, lib, ... }:
{
  imports = [
    ./hyprland.nix
  ];

  # Enable greetd as the display manager
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };
  };
  
  # Create the greeter user and group
  users.users.greeter = {
    isSystemUser = true;
    group = "greeter";
    description = "TUI Greeter user";
  };
  
  users.groups.greeter = {};
  
  # Disable SDDM
  services.displayManager.sddm.enable = lib.mkForce false;

  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Common packages for GUI environments
  environment.systemPackages = with pkgs; [
    # Display manager
    greetd.tuigreet
    
    # Essential GUI utilities
    xdg-utils
    libsForQt5.qt5.qtwayland
    qt6.qtwayland

    # Default icon themes for better app appearance
    hicolor-icon-theme
    adwaita-icon-theme
  ];

  # Enable fonts
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
  ];

  # Enable graphics drivers for better Wayland support
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}

