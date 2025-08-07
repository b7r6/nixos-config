{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.hyprland;
  inherit (config.lib.stylix) colors;
  base02 = lib.removePrefix "#" colors.base02;
  base0D = lib.removePrefix "#" colors.base0D;
  base0E = lib.removePrefix "#" colors.base0E;
in
{
  options.hyper-modern-nixos.hyprland = {
    enable = mkEnableOption "hyper-modern-nixos.hyprland" // {
      default = false;
      description = "Enable system-level Hyprland configuration";
    };

    monitors = mkOption {
      type = types.listOf types.str;
      default = [ "desc:LG Electronics LG ULTRAGEAR+ 502NTMX7E483,0x0@60,0x0,2.0" ];
      description = "Monitor configuration strings";
    };

    workspaces = mkOption {
      type = types.listOf types.str;
      default = [
        "1, monitor:desc:LG Electronics LG ULTRAGEAR+ 502NTMX7E483, default:true, persistent:true"
        "2, monitor:desc:LG Electronics LG ULTRAGEAR+ 502NTMX7E483, persistent:true"
        "3, monitor:desc:LG Electronics LG ULTRAGEAR+ 502NTMX7E483, persistent:true"
        "4, monitor:desc:LG Electronics LG ULTRAGEAR+ 502NTMX7E483, persistent:true"
        "5, monitor:desc:LG Electronics LG ULTRAGEAR+ 502NTMX7E483, persistent:true"
        "6, monitor:desc:LG Electronics LG ULTRAGEAR+ 502NTMX7E483, persistent:true"
      ];
      description = "Workspace configuration strings";
    };
  };

  config = mkIf cfg.enable {
    programs.hyprland = {
      enable = true;
      package = pkgs.hyprland;
    };

    # Create system-wide Hyprland configuration
    environment.etc."hypr/hyprland.conf".text = ''
      # Monitor configuration
      ${concatMapStringsSep "\n" (monitor: "monitor=${monitor}") cfg.monitors}

      # Workspace configuration
      ${concatMapStringsSep "\n" (workspace: "workspace=${workspace}") cfg.workspaces}

      # Startup applications
      exec-once = waybar
      exec-once = mako
      exec-once = wl-paste --type text --watch cliphist store & wl-paste --type image --watch cliphist store

      # General settings
      general {
        border_size = 2
        gaps_in = 4
        gaps_out = 8
        layout = dwindle
        resize_on_border = true
        
        col.active_border = rgba(${base0D}ff) rgba(${base0E}ff) 45deg
        col.inactive_border = rgba(${base02}66)
      }

      # Decoration
      decoration {
        rounding = 0
        
        blur {
          enabled = true
          size = 8
          passes = 2
          new_optimizations = true
          xray = true
          ignore_opacity = false
          brightness = 0.8
          contrast = 1.2
          noise = 0.01
        }
        
        active_opacity = 1.0
        inactive_opacity = 0.85
        fullscreen_opacity = 1.0
      }

      # Animations
      animations {
        enabled = true
        
        bezier = easeOutQuint, 0.22, 1, 0.36, 1
        bezier = easeInOutQuint, 0.83, 0, 0.17, 1
        bezier = easeOutExpo, 0.16, 1, 0.3, 1
        
        animation = windows, 1, 3, easeOutExpo, popin 80%
        animation = windowsOut, 1, 3, easeOutExpo, popin 80%
        animation = border, 1, 5, easeOutQuint
        animation = fade, 1, 3, easeInOutQuint
        animation = workspaces, 1, 3, easeOutExpo, slide
        animation = specialWorkspace, 1, 3, easeOutExpo, slidevert
      }

      # Input settings
      input {
        kb_layout = us
        follow_mouse = 1
        sensitivity = 0
        accel_profile = flat
        mouse_refocus = false
        
        touchpad {
          natural_scroll = true
          disable_while_typing = true
          clickfinger_behavior = true
          tap-to-click = true
          drag_lock = true
        }
        
        kb_options = ctrl:nocaps
      }

      # Gestures
      gestures {
        workspace_swipe = true
        workspace_swipe_fingers = 3
        workspace_swipe_distance = 300
        workspace_swipe_invert = false
        workspace_swipe_create_new = false
      }

      # Misc settings
      misc {
        force_default_wallpaper = 0
        animate_mouse_windowdragging = false
        animate_manual_resizes = false
        enable_swallow = true
        swallow_regex = ^(wezterm|ghostty|alacritty|foot|kitty)$
        focus_on_activate = true
        disable_hyprland_logo = true
        disable_splash_rendering = true
        vfr = true
        vrr = 1
        mouse_move_enables_dpms = true
        key_press_enables_dpms = true
      }

      # Key bindings
      $mod = SUPER
      $alt = ALT

      # Core bindings
      bind = $mod, Return, exec, wezterm
      bind = $mod SHIFT, Return, exec, [float] wezterm
      bind = $mod, Space, exec, wofi --show drun
      bind = $mod SHIFT, Space, exec, wofi --show run
      bind = $mod, E, exec, nemo
      bind = $mod, W, exec, firefox
      bind = $mod, BackSpace, killactive
      bind = $mod SHIFT, BackSpace, exit

      # Window states
      bind = $mod, F, fullscreen, 0
      bind = $mod SHIFT, F, fullscreen, 1
      bind = $mod, D, togglefloating
      bind = $mod, P, pin
      bind = $mod, C, centerwindow

      # Monitor navigation
      bind = $mod, comma, focusmonitor, -1
      bind = $mod, period, focusmonitor, +1

      # Move windows between monitors
      bind = $mod SHIFT, comma, movewindow, mon:-1
      bind = $mod SHIFT, period, movewindow, mon:+1

      # Workspace switching
      bind = $mod, Tab, workspace, m+1
      bind = $mod SHIFT, Tab, workspace, m-1

      # Direct workspace access
      bind = $mod, 1, workspace, 1
      bind = $mod, 2, workspace, 2
      bind = $mod, 3, workspace, 3
      bind = $mod, 4, workspace, 4
      bind = $mod, 5, workspace, 5
      bind = $mod, 6, workspace, 6
      bind = $mod, 7, workspace, 7
      bind = $mod, 8, workspace, 8
      bind = $mod, 9, workspace, 9
      bind = $mod, 0, workspace, 10

      # Move windows to workspaces
      bind = $mod SHIFT, 1, movetoworkspace, 1
      bind = $mod SHIFT, 2, movetoworkspace, 2
      bind = $mod SHIFT, 3, movetoworkspace, 3
      bind = $mod SHIFT, 4, movetoworkspace, 4
      bind = $mod SHIFT, 5, movetoworkspace, 5
      bind = $mod SHIFT, 6, movetoworkspace, 6
      bind = $mod SHIFT, 7, movetoworkspace, 7
      bind = $mod SHIFT, 8, movetoworkspace, 8
      bind = $mod SHIFT, 9, movetoworkspace, 9
      bind = $mod SHIFT, 0, movetoworkspace, 10

      # Window focus - vim keys
      bind = $mod, H, movefocus, l
      bind = $mod, L, movefocus, r
      bind = $mod, K, movefocus, u
      bind = $mod, J, movefocus, d

      # Move windows - vim keys
      bind = $mod SHIFT, H, movewindow, l
      bind = $mod SHIFT, L, movewindow, r
      bind = $mod SHIFT, K, movewindow, u
      bind = $mod SHIFT, J, movewindow, d

      # Resize windows - vim keys with ALT
      bind = $mod $alt, H, resizeactive, -30 0
      bind = $mod $alt, L, resizeactive, 30 0
      bind = $mod $alt, K, resizeactive, 0 -30
      bind = $mod $alt, J, resizeactive, 0 30

      # Screenshots
      bind = $mod, S, exec, grim -g "$(slurp)" - | wl-copy
      bind = $mod SHIFT, S, exec, grim -g "$(slurp)" ~/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png
      bind = $mod $alt, S, exec, grim - | wl-copy
      bind = $mod $alt SHIFT, S, exec, grim ~/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png

      # Media controls
      bind = , XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+
      bind = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
      bind = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
      bind = , XF86AudioPlay, exec, playerctl play-pause
      bind = , XF86AudioNext, exec, playerctl next
      bind = , XF86AudioPrev, exec, playerctl previous

      # Brightness
      bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
      bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

      # Lock screen
      bind = $mod, Escape, exec, swaylock-effects --screenshots --clock --effect-blur 7x5

      # Mouse bindings
      bindm = $mod, mouse:272, movewindow
      bindm = $mod, mouse:273, resizewindow
      bindm = $mod SHIFT, mouse:272, resizewindow

      # Window rules
      windowrulev2 = workspace 1, class:^(firefox)$
      windowrulev2 = workspace 2, class:^(Code|code-url-handler)$
      windowrulev2 = workspace 9, class:^(discord|Discord)$
      windowrulev2 = workspace 10, class:^(Spotify|spotify)$

      # Float specific windows
      windowrulev2 = float, class:^(pavucontrol)$
      windowrulev2 = float, class:^(nm-connection-editor)$
      windowrulev2 = float, class:^(.blueman-manager-wrapped)$
      windowrulev2 = float, title:^(Picture-in-Picture)$

      # PiP rules
      windowrulev2 = float, title:^(Picture-in-Picture)$
      windowrulev2 = pin, title:^(Picture-in-Picture)$
      windowrulev2 = size 560 315, title:^(Picture-in-Picture)$
      windowrulev2 = move 100%-576 100%-331, title:^(Picture-in-Picture)$
    '';

    # Enable system packages that Hyprland needs
    environment.systemPackages = with pkgs; [
      brightnessctl
      grim
      slurp
      swappy
      wl-clipboard
      cliphist
      playerctl
      wireplumber
      pavucontrol
      wezterm
      nemo
      firefox
      swaylock-effects
      wofi
    ];
  };
}
