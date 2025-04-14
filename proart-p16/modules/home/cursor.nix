# Cursor theme configuration for the ProArt P16
{ config, lib, pkgs, ... }:

{
  options.cursor = {
    enable = lib.mkEnableOption "Enable custom cursor theme";
    
    # Cursor theme selection
    theme = lib.mkOption {
      type = lib.types.str;
      default = "Bibata-Modern-Ice";
      description = "Name of the cursor theme to use";
      example = "Bibata-Modern-Classic";
    };
    
    # Cursor size
    size = lib.mkOption {
      type = lib.types.int;
      default = 24;
      description = "Cursor size in pixels";
      example = 32;
    };
    
    # Cursor animation speed in ms (lower = faster)
    animationSpeed = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Cursor animation speed (ms, 0 to disable)";
      example = 5;
    };
  };

  config = lib.mkIf config.cursor.enable {
    # Install cursor themes
    home.packages = with pkgs; [
      bibata-cursors           # High-quality cursor set
      nordzy-cursor-theme      # Nordic-style cursor theme
      vanilla-dmz              # Classic cursor theme
      capitaine-cursors        # macOS-like cursor theme
    ];
    
    # Set cursor theme for X11 - works without requiring GNOME/GTK
    xsession.pointerCursor = {
      name = config.cursor.theme;
      package = pkgs.bibata-cursors;
      size = config.cursor.size;
    };
    
    # Set environment variables for cursor theme
    home.sessionVariables = {
      XCURSOR_THEME = config.cursor.theme;
      XCURSOR_SIZE = toString config.cursor.size;
    };
    
    # Configure cursor animation speed in Hyprland
    wayland.windowManager.hyprland.settings = lib.mkIf 
      (config.wayland.windowManager.hyprland.enable or false) {
        input = {
          cursor_inactive_timeout = 4; # seconds until cursor hides when inactive
        };
        
        general = {
          cursor_inactive_timeout = 4;
          apply_sens_to_raw = 0;  # Apply sensitivity to raw input (0 if using libinput)
        };
        
        misc = {
          animate_mouse_windowdragging = true;
          animate_manual_resizes = true;
          vfr = true;
        };
    };
    
    # Configure cursor theme path - works for all window managers
    home.file.".icons/default/index.theme".text = ''
      [Icon Theme]
      Name=Default
      Comment=Default Cursor Theme
      Inherits=${config.cursor.theme}
    '';
    
    # Add additional configuration for Hyprland
    wayland.windowManager.hyprland.extraConfig = lib.mkIf 
      (config.wayland.windowManager.hyprland.enable or false)
      ''
      # Mouse and cursor settings
      env = XCURSOR_THEME,${config.cursor.theme}
      env = XCURSOR_SIZE,${toString config.cursor.size}
      
      # Better cursor warp behavior
      misc {
        cursor_zoom_factor = 1.0
        cursor_zoom_rigid = false
        mouse_move_enables_dpms = true
        key_press_enables_dpms = true
        new_window_takes_over_fullscreen = 2
      }
      '';
  };
} 