# Keyboard remapping configuration for the ProArt P16
{ config, lib, pkgs, ... }:

{
  options.keyboard = {
    enable = lib.mkEnableOption "Enable keyboard remapping";
    
    # Add more options for additional key remaps as needed
    capsToCtrl = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Remap Caps Lock to Control";
    };
    
    # Optional: Swap Escape and Caps Lock
    escToCaps = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Swap Escape and Caps Lock (will override capsToCtrl if both are true)";
    };
    
    # Optional: Swap Alt and Super keys (Win/Command)
    swapAltSuper = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Swap Alt and Super (Windows/Command) keys";
    };
  };

  config = lib.mkIf config.keyboard.enable {
    # X11 configuration for standard desktop environments
    services.xserver.xkbOptions = lib.mkIf (config.services.xserver.enable or false) 
      (lib.concatStringsSep "," (lib.flatten [
        (lib.optional config.keyboard.capsToCtrl "ctrl:nocaps")
        (lib.optional config.keyboard.escToCaps "caps:swapescape")
        (lib.optional config.keyboard.swapAltSuper "altwin:swap_alt_win")
      ]));
    
    # Home Manager configuration for X11/Wayland
    home.keyboard = {
      options = lib.flatten [
        (lib.optional config.keyboard.capsToCtrl "ctrl:nocaps")
        (lib.optional config.keyboard.escToCaps "caps:swapescape")
        (lib.optional config.keyboard.swapAltSuper "altwin:swap_alt_win")
      ];
    };
    
    # Hyprland-specific configuration (if Hyprland is enabled)
    wayland.windowManager.hyprland.settings = lib.mkIf 
      (config.wayland.windowManager.hyprland.enable or false) {
        input = {
          kb_options = lib.concatStringsSep "," (lib.flatten [
            (lib.optional config.keyboard.capsToCtrl "ctrl:nocaps")
            (lib.optional config.keyboard.escToCaps "caps:swapescape")
            (lib.optional config.keyboard.swapAltSuper "altwin:swap_alt_win")
          ]);
        };
      };
    
    # For when none of the above methods apply, use interception-tools
    home.packages = [
      pkgs.interception-tools
      pkgs.interception-tools-plugins.caps2esc
    ];
    
    # Create a udev rule for interception-tools
    home.file.".config/interception-tools/udevmon.yaml".text = let
      caps2escConfig = if config.keyboard.capsToCtrl 
                      then "-m 1"   # Mode 1: Caps -> Ctrl
                      else if config.keyboard.escToCaps
                      then ""       # Default: Caps -> Esc, Esc -> Caps
                      else null;
    in
      lib.optionalString (caps2escConfig != null) ''
        - JOB: "${pkgs.interception-tools}/bin/intercept -g $DEVNODE | ${pkgs.interception-tools-plugins.caps2esc}/bin/caps2esc ${caps2escConfig} | ${pkgs.interception-tools}/bin/uinput -d $DEVNODE"
          DEVICE:
            EVENTS:
              EV_KEY: [KEY_CAPSLOCK, KEY_ESC]
      ''
      + lib.optionalString config.keyboard.swapAltSuper ''
        - JOB: "${pkgs.interception-tools}/bin/intercept -g $DEVNODE | ${pkgs.interception-tools}/bin/uinput -d $DEVNODE"
          DEVICE:
            EVENTS:
              EV_KEY: [KEY_LEFTALT, KEY_LEFTMETA, KEY_RIGHTALT, KEY_RIGHTMETA]
      '';
      
    # Autostart udevmon (for interception-tools) in user session if Hyprland is used
    wayland.windowManager.hyprland.extraConfig = lib.mkIf 
      (config.wayland.windowManager.hyprland.enable or false)
      ''
      # Start interception-tools for keyboard remapping
      exec-once = ${pkgs.interception-tools}/bin/udevmon -c $HOME/.config/interception-tools/udevmon.yaml
      '';
  };
} 