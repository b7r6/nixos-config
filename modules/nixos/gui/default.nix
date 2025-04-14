# GUI module for NixOS
{ pkgs, lib, ... }:
{
  imports = [
    ./gnome.nix
    ./hyprland.nix
  ];

  # Configure display manager (login screen)
  services.displayManager = {
    # Enable SDDM
    sddm = {
      enable = true;
      # Wayland support
      wayland.enable = true;

      # Theme settings
      theme = "breeze";

      # Configure to properly handle Wayland sessions including Hyprland
      settings = {
        General = {
          DisplayServer = "wayland";
          InputMethod = "";
        };
        Wayland = {
          CompositorCommand = "kwin_wayland --drm --no-lockscreen";
          SessionDir = "/run/current-system/sw/share/wayland-sessions";
        };
      };
    };

    # Default to Hyprland session if available
    defaultSession = lib.mkForce "hyprland";
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Common packages for GUI environments
  environment.systemPackages = with pkgs; [
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
