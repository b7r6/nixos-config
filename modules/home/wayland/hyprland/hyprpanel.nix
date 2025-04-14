{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
  ];

  programs.hyprpanel = {

    # Enable the module.
    # Default: false
    enable = true;
    overlay.enable = true;

    # Automatically restart HyprPanel with systemd.
    # Useful when updating your config so that you
    # don't need to manually restart it.
    # Default: false
    systemd.enable = true;

    # Add '/nix/store/.../hyprpanel' to your
    # Hyprland config 'exec-once'.
    # Default: false
    hyprland.enable = true;

    # Fix the overwrite issue with HyprPanel.
    # See below for more information.
    # Default: false
    overwrite.enable = true;
  };
}
