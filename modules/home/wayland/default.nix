# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                               // hyper-modern-nixos // wayland
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Wayland desktop environment configuration.
# Provides high-level options for Hyprland and supporting tools.
#
{ lib, ... }: {
  imports = [
    ./hyprland
    ./hyprland/waybar.nix
    ./hyprland/launchers.nix
    ./hyprland/notifications.nix
    ./hyprland/lockscreen.nix
  ];

  # Top-level wayland options for backward compatibility
  options.wayland = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Wayland desktop environment";
    };

    hyprland.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Hyprland window manager";
    };
  };
}
