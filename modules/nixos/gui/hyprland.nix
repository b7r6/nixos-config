{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
  ];

  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Environment variables for Wayland compatibility
  environment.sessionVariables = {
    # For Wayland applications
    NIXOS_OZONE_WL = "1";

    # For QT apps
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";

    # For Firefox
    MOZ_ENABLE_WAYLAND = "1";

    # For SDL
    SDL_VIDEODRIVER = "wayland";

    # For Java applications
    _JAVA_AWT_WM_NONREPARENTING = "1";

    # For Elementary/EFL
    ECORE_EVAS_ENGINE = "wayland";
    ELM_ENGINE = "wayland";
  };

  # Essential packages for Hyprland
  environment.systemPackages = with pkgs; [
    # Core components
    hyprpaper # Wallpaper tool
    waybar # Status bar
    wofi # Application launcher
    wl-clipboard # Clipboard

    # Screenshot/screen recording
    grim # Screenshot utility
    slurp # Area selection
    swappy # Screenshot editing

    # Notification daemon
    mako

    # System utilities
    brightnessctl # Brightness control
    pamixer # Volume control
    playerctl # Media player control
    xdg-desktop-portal-hyprland # XDG portal

    # File manager that works well with Wayland
    pcmanfm

    # Terminal emulator with Wayland support
    foot

    # Useful utilities
    libnotify
  ];

  # Important for screen sharing and recording
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    config.common.default = "*";
  };

  # Enable polkit for authentication dialogs
  security.polkit.enable = true;

  environment.etc."hypr/hyprland.conf".text = ''
    # Monitor configuration
    monitor=,preferred,auto,1

    # Execute at launch
    exec-once = hyprpaper & waybar & mako

    # Input configuration
    input {
        kb_layout = us
        follow_mouse = 1
        touchpad {
            natural_scroll = true
        }
    }

    # General configuration
    general {
        gaps_in = 5
        gaps_out = 10
        border_size = 2
        col.active_border = rgba(33ccffee)
        col.inactive_border = rgba(595959aa)
        layout = dwindle
    }

    # Misc settings
    misc {
        disable_hyprland_logo = true
        disable_splash_rendering = true
    }

    # Window rules
    windowrule = float, ^(pavucontrol)$
    windowrule = float, ^(nm-connection-editor)$
    windowrule = float, ^(galculator)$

    # Basic keybindings
    bind = SUPER, Return, exec, foot
    bind = SUPER, Q, killactive
    bind = SUPER, space, exec, wofi --show drun
    bind = SUPER, F, fullscreen
    bind = SUPER SHIFT, E, exit

    # Move focus
    bind = SUPER, left, movefocus, l
    bind = SUPER, right, movefocus, r
    bind = SUPER, up, movefocus, u
    bind = SUPER, down, movefocus, d

    # Move windows
    bind = SUPER SHIFT, left, movewindow, l
    bind = SUPER SHIFT, right, movewindow, r
    bind = SUPER SHIFT, up, movewindow, u
    bind = SUPER SHIFT, down, movewindow, d

    # Resize windows
    bindm = SUPER, mouse:272, movewindow
    bindm = SUPER, mouse:273, resizewindow

    # Switch workspaces
    bind = SUPER, 1, workspace, 1
    bind = SUPER, 2, workspace, 2
    bind = SUPER, 3, workspace, 3
    bind = SUPER, 4, workspace, 4
    bind = SUPER, 5, workspace, 5

    # Move windows to workspaces
    bind = SUPER SHIFT, 1, movetoworkspace, 1
    bind = SUPER SHIFT, 2, movetoworkspace, 2
    bind = SUPER SHIFT, 3, movetoworkspace, 3
    bind = SUPER SHIFT, 4, movetoworkspace, 4
    bind = SUPER SHIFT, 5, movetoworkspace, 5
  '';
}
