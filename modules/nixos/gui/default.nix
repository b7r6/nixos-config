# Minimalist Wayland-first GUI module
{ pkgs, lib, config, ... }:

with lib;
let
  cfg = config.services.gui;
in
{
  # No default imports - explicitly choose what you need
  imports = [ ];

  options.services.gui = {
    enable = mkEnableOption "GUI environment";
  };

  config = mkIf cfg.enable {
    # Wayland-first minimal configuration
    
    # Common packages for Wayland
    environment.systemPackages = with pkgs; [
      # Essential GUI utilities
      xdg-utils
      
      # Wayland toolkit support
      qt6.qtwayland
      
      # Basic utilities
      wl-clipboard # Clipboard manager
      
      # Default icon themes for better app appearance
      hicolor-icon-theme
      adwaita-icon-theme
    ];

    # Wayland environment variables
    environment.sessionVariables = {
      # For electron apps and other Ozone-based apps
      NIXOS_OZONE_WL = "1";
      
      # For Firefox
      MOZ_ENABLE_WAYLAND = "1";
      
      # For Java applications
      _JAVA_AWT_WM_NONREPARENTING = "1";
    };

    # Basic fonts that most systems need
    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      liberation_ttf
      fira-code
    ];
    
    # Enable graphics drivers with hardware acceleration
    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };
  };
}