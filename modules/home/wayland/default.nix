{ lib, ... }:
{
  imports = [ ./hyprland ];

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
  };
}
