{ lib, ... }:
{
  options.wayland = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Wayland desktop environments";
    };

    hyprland = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Hyprland window manager";
      };
    };

    plasma = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable KDE Plasma desktop environment";
      };
    };
  };

  imports = [
    ./hyprland
    ./plasma.nix
  ];
}
