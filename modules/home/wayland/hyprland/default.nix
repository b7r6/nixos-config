{ flake, config, lib, pkgs, ... }:

# 1. **Zero Border Radius**: Removed all rounded corners throughout Hyprland, Waybar, notifications, and application launcher.

# 2. **Minimal Gaps**: Set to just 2px for both inner and outer gaps.

# 3. **Strong Vim-style Navigation**:
#    - `Super+H,J,K,L` for window focus
#    - `Super+Shift+H,J,K,L` for moving windows
#    - `Super+Alt+H,J,K,L` for resizing windows

# 4. **Monitor Management**:
#    - Persistent workspaces per monitor (1-3 on external, 4-6 on laptop)
#    - `Super+,/.` to switch between monitors
#    - `Super+Shift+,/.` to move workspaces between monitors

# 5. **Improved Layout Controls**:
#    - `Super+V` for vertical split
#    - `Super+B` for horizontal split
#    - `Super+T` for tabbed layout
#    - `Super+G` to change group layout type
#    - `Super+R` to rotate focus within a group

# 6. **Special Workspace (Scratchpad)**:
#    - `Super+S` to toggle special workspace
#    - Auto-spawns terminal in empty special workspace

# 7. **Workspace Controls**:
#    - `Super+Tab` / `Super+Shift+Tab` to cycle workspaces on current monitor
#    - `Super+Alt+Tab` to cycle through all workspaces

# 8. **Clean, Minimal UI**:
#    - Simple Waybar with basic information
#    - Minimal animations for better performance
#    - Flat, square design throughout

let
  cfg = config.wayland.hyprland;
  inherit (flake) inputs;

  # Extract color values without # prefix for Hyprland
  inherit (config.lib.stylix) colors;
  base00 = lib.removePrefix "#" colors.base00; # background
  base01 = lib.removePrefix "#" colors.base01; # lighter background
  base02 = lib.removePrefix "#" colors.base02; # selection background
  base03 = lib.removePrefix "#" colors.base03; # comments/dark
  base04 = lib.removePrefix "#" colors.base04; # dark foreground
  base05 = lib.removePrefix "#" colors.base05; # foreground
  base06 = lib.removePrefix "#" colors.base06; # light foreground
  base07 = lib.removePrefix "#" colors.base07; # light background
  base08 = lib.removePrefix "#" colors.base08; # red
  base09 = lib.removePrefix "#" colors.base09; # orange
  base0A = lib.removePrefix "#" colors.base0A; # yellow
  base0B = lib.removePrefix "#" colors.base0B; # green
  base0C = lib.removePrefix "#" colors.base0C; # cyan
  base0D = lib.removePrefix "#" colors.base0D; # blue
  base0E = lib.removePrefix "#" colors.base0E; # purple
  base0F = lib.removePrefix "#" colors.base0F; # dark accent

  # Monitor setup script
  monitorSetupScript = pkgs.writeShellScript "hyprland-monitor-setup" ''
    #!/usr/bin/env bash
    
    # Wait for monitors to connect
    sleep 1
    
    # Check for monitors
    PRIMARY_MONITOR="desc:AOC CU34G2XP"
    LAPTOP_MONITOR="eDP-1"
    
    if hyprctl monitors -j | grep -q "$PRIMARY_MONITOR"; then
      # External monitor present - set it up
      hyprctl dispatch workspace 1
      hyprctl dispatch focusmonitor "$PRIMARY_MONITOR"
    else
      # Only laptop monitor
      hyprctl dispatch workspace 4
      hyprctl dispatch focusmonitor "$LAPTOP_MONITOR"
    fi
  '';
in
{
  imports = [
    inputs.hyprland.homeManagerModules.default
  ];

  wayland.windowManager.hyprland = {
    enable = cfg.enable;
    systemd.enable = true;

    plugins = [
      inputs.hy3.outputs.packages.${pkgs.system}.hy3
    ];

    settings = {
      # ===== Monitor Configuration =====
      monitor = [
        # External monitor - WQHD ultrawide
        "desc:AOC CU34G2XP,3440x1440@100.00,0x0,1.5"

        # Laptop display with scaled resolution
        "eDP-1,3840x2400@60.00,3440x0,2.5"

        # Fallback for other monitors
        ",preferred,auto,1"
      ];

      # ===== Persistent Workspace Assignment =====
      # First three workspaces for external, next three for laptop
      workspace = [
        "1, monitor:desc:AOC CU34G2XP, default:true, persistent:true"
        "2, monitor:desc:AOC CU34G2XP, persistent:true"
        "3, monitor:desc:AOC CU34G2XP, persistent:true"
        "4, monitor:eDP-1, default:true, persistent:true"
        "5, monitor:eDP-1, persistent:true"
        "6, monitor:eDP-1, persistent:true"
        # Special workspace can be summoned anywhere
        "special, on-created-empty:wezterm"
      ];

      # ===== Handle laptop lid =====
      bindl = [
        ",switch:off:Lid Switch,exec,hyprctl keyword monitor eDP-1 disable"
        ",switch:on:Lid Switch,exec,hyprctl keyword monitor eDP-1 3840x2400@60.00,3440x0,2.5"
      ];

      # ===== Startup Programs =====
      exec-once = [
        "blueman-applet"
        "hyprpaper"
        "mako"
        "nm-tray"
        "tailscale-systray"
        "waybar"
        "${monitorSetupScript}"
      ];

      # ===== General UI Settings =====
      general = {
        gaps_in = 1-;
        gaps_out = 10;
        border_size = 2;
        resize_on_border = true;

        # Use the hy3 plugin for layout
        layout = "hy3";
      };

      # ===== UI Theme Elements =====
      decoration = {
        rounding = 0; # No rounded corners

        blur = {
          enabled = true;
          size = 3;
          passes = 1;
          new_optimizations = true;
          xray = false;
          ignore_opacity = true;
        };

        # Focus indication
        active_opacity = 1.0;
        inactive_opacity = 0.95;
        fullscreen_opacity = 1.0;
      };

      # ===== Animations =====
      animations = {
        enabled = true;

        bezier = [
          "easeOutQuint, 0.22, 1, 0.36, 1"
        ];

        animation = [
          "windows, 1, 3, easeOutQuint"
          "windowsOut, 1, 3, easeOutQuint"
          "border, 1, 3, easeOutQuint"
          "fade, 1, 3, easeOutQuint"
          "workspaces, 1, 3, easeOutQuint"
          "specialWorkspace, 1, 3, easeOutQuint"
        ];
      };

      # ===== Input Settings =====
      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
        accel_profile = "flat";

        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
          clickfinger_behavior = true;
          tap-to-click = true;
          drag_lock = true;
        };

        kb_options = "ctrl:nocaps";
      };

      # ===== Touchpad Gestures =====
      gestures = {
        workspace_swipe = true;
        workspace_swipe_fingers = 3;
        workspace_swipe_distance = 300;
        workspace_swipe_invert = false;
        workspace_swipe_create_new = false;
      };

      # ===== Misc Settings =====
      misc = {
        force_default_wallpaper = 0;
        animate_mouse_windowdragging = false;
        animate_manual_resizes = false;
        enable_swallow = true;
        swallow_regex = "^(wezterm|kitty|alacritty)$";
        focus_on_activate = true;
      };

      # ===== HY3 Plugin Settings =====
      plugin.hy3 = {
        # Enable vim-like behavior
        vim_bindings = true;
        node_collapse_policy = 2; # Only collapse if empty

        # Tab configuration
        tabs = {
          height = 16;
          padding = 0;
          from_top = true;
          rounding = 0; # No rounding
          render_text = true;

          # Tab colors
          "col.active" = "rgba(${base0D}ee)";
          "col.inactive" = "rgba(${base02}aa)";
          "col.text.active" = "rgba(${base05}ee)";
          "col.text.inactive" = "rgba(${base04}aa)";

          "col.active_border" = "rgba(${base0D}ee) rgba(${base0E}ee) 45deg";
          "col.inactive_border" = "rgba(${base02}aa)";
          border_width = 1;
        };

        # Automatic tiling
        autotile = {
          enable = true;
          trigger_width = 800;
          main_ratio = 0.5;
        };
      };

      # ===== Key Bindings =====
      "$mod" = "SUPER";
      "$alt" = "ALT";

      # Core system bindings
      bind = [
        # Applications
        "$mod, Return, exec, wezterm"
        "$mod, Space, exec, wofi --show drun"
        "$mod, E, exec, dolphin"
        "$mod, W, exec, firefox"
        "$mod, BackSpace, killactive"
        "$mod SHIFT, BackSpace, exit"

        # Special workspace (scratchpad)
        "$mod, S, togglespecialworkspace"
        "$mod SHIFT, S, movetoworkspace, special"

        # Fullscreen and floating
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, fullscreen, 1"
        "$mod, D, togglefloating"

        # Monitor navigation (vim-inspired)
        "$mod, comma, focusmonitor, -1"
        "$mod, period, focusmonitor, +1"

        # Move current workspace to next/prev monitor
        "$mod SHIFT, comma, movecurrentworkspacetomonitor, -1"
        "$mod SHIFT, period, movecurrentworkspacetomonitor, +1"

        # Workspace switching - per monitor
        "$mod, Tab, workspace, m+1"
        "$mod SHIFT, Tab, workspace, m-1"

        # Workspace switching - global
        "$mod $alt, Tab, workspace, +1"
        "$mod $alt SHIFT, Tab, workspace, -1"

        # Direct workspace access
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"

        # Move windows to workspaces
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"

        # Window focus - vim keys
        "$mod, H, hy3:movefocus, l"
        "$mod, L, hy3:movefocus, r"
        "$mod, K, hy3:movefocus, u"
        "$mod, J, hy3:movefocus, d"

        # Move windows - vim keys
        "$mod SHIFT, H, hy3:movewindow, l"
        "$mod SHIFT, L, hy3:movewindow, r"
        "$mod SHIFT, K, hy3:movewindow, u"
        "$mod SHIFT, J, hy3:movewindow, d"

        # Resize windows - vim keys with ALT
        "$mod $alt, H, resizeactive, -20 0"
        "$mod $alt, L, resizeactive, 20 0"
        "$mod $alt, K, resizeactive, 0 -20"
        "$mod $alt, J, resizeactive, 0 20"

        # Layout control
        "$mod, T, hy3:makegroup, tab" # Create tabbed group
        "$mod, G, hy3:changegroup, opposite" # Change group layout (h/v/tab)

        # Screenshots
        ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
        "$mod, Print, exec, grim -g \"$(slurp)\" ~/Pictures/screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png"
        "SHIFT, Print, exec, grim - | wl-copy"

        # Media controls
        ", XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%"
        ", XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%"
        ", XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"

        # Brightness controls
        ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
      ];

      # Mouse bindings
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };
  };

  # ===== WAYBAR CONFIGURATION =====
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 28;
        spacing = 2;

        modules-left = [
          "hyprland/workspaces"
          "hyprland/window"
        ];

        modules-center = [ "clock" ];

        modules-right = [
          "battery"
          "network"
          "cpu"
          "memory"
          "pulseaudio"
          "tray"
        ];

        "hyprland/workspaces" = {
          format = "{name}";
          on-click = "activate";
          sort-by-number = true;
          all-outputs = false;
          active-only = false;
        };

        "clock" = {
          format = "{:%H:%M}";
          format-alt = "{:%Y-%m-%d}";
          tooltip-format = "{:%Y-%m-%d | %H:%M}";
          on-click = "mode";
        };

        "cpu" = {
          format = "CPU {usage}%";
          tooltip = true;
          interval = 2;
        };

        "memory" = {
          format = "MEM {used:0.1f}GB";
          interval = 2;
        };

        "battery" = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "BAT {capacity}%";
          format-charging = "CHG {capacity}%";
          format-plugged = "PLUG {capacity}%";
        };

        "network" = {
          format-wifi = "WIFI {essid}";
          format-ethernet = "ETH {ipaddr}";
          format-linked = "ETH (No IP)";
          format-disconnected = "NET Disconnected";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}";
          max-length = 50;
          interval = 5;
        };

        "pulseaudio" = {
          format = "VOL {volume}%";
          format-muted = "MUTED";
          on-click = "pavucontrol";
        };

        "tray" = {
          icon-size = 16;
          spacing = 5;
        };
      };
    };

    style = ''
      * {
        font-family: "${config.stylix.fonts.monospace.name}", monospace;
        font-size: ${toString config.stylix.fonts.sizes.applications}px;
        border-radius: 0px;
      }

      window#waybar {
        background-color: #${colors.base00};
        color: #${colors.base05};
        border-bottom: 1px solid #${colors.base02};
      }

      #workspaces button {
        padding: 0 5px;
        background-color: transparent;
        color: #${colors.base05};
        border-bottom: 1px solid #${colors.base02};
      }

      #workspaces button:hover {
        background: #${colors.base01};
      }

      #workspaces button.active {
        background-color: #${colors.base02};
        border-bottom: 1px solid #${colors.base0D};
      }

      #workspaces button.urgent {
        background-color: #${colors.base08};
      }

      #clock,
      #battery,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #tray {
        padding: 0 5px;
        margin: 0 2px;
        color: #${colors.base05};
      }

      #window {
        margin-left: 5px;
        color: #${colors.base05};
      }

      #battery.critical:not(.charging) {
        background-color: #${colors.base08};
        color: #${colors.base00};
      }
    '';
  };

  # ===== Notification daemon (mako) =====
  services.mako = {
    enable = true;
    borderSize = 1;
    borderRadius = 0;
    padding = "5";
    defaultTimeout = 5000;
    layer = "overlay";

    # backgroundColor = "#${colors.base00}";
    textColor = "#${colors.base05}";
    borderColor = "#${colors.base0D}";

    extraConfig = ''
      [urgency=low]
      border-color=#${colors.base0D}

      [urgency=normal]
      border-color=#${colors.base0D}

      [urgency=high]
      border-color=#${colors.base08}
      default-timeout=0
    '';
  };

  # ===== Wofi Configuration =====
  home.file.".config/wofi/style.css".text = ''
    window {
      margin: 0px;
      background-color: #${colors.base00};
      border: 1px solid #${colors.base0D};
      border-radius: 0px;
    }

    #input {
      margin: 5px;
      border: 1px solid #${colors.base02};
      border-radius: 0px;
      color: #${colors.base05};
      background-color: #${colors.base01};
    }

    #inner-box {
      margin: 2px;
      background-color: #${colors.base00};
      border-radius: 0px;
    }

    #outer-box {
      margin: 2px;
      padding: 5px;
      background-color: #${colors.base00};
      border-radius: 0px;
    }

    #scroll {
      margin: 2px;
      background-color: #${colors.base00};
    }

    #text {
      margin: 2px;
      color: #${colors.base05};
    }

    #entry:selected {
      background-color: #${colors.base02};
    }

    #text:selected {
      color: #${colors.base0D};
    }
  '';

  # ===== Required packages =====
  home.packages = with pkgs; [
    # System tray applets
    blueman
    nm-tray
    tailscale-systray

    # Tools and utilities
    brightnessctl
    grim # Screenshot tool
    hyprpaper # Wallpaper
    mako # Notifications
    pavucontrol # Audio control
    playerctl # Media control
    slurp # Screen area selection
    waybar # Status bar
    wl-clipboard # Clipboard tools
    wofi # Application launcher

    # Additional helpful tools
    jq # JSON processing
    libnotify # Notifications
    pamixer # Pulseaudio control
    swappy # Screenshot editing
    wev # Input debugger
    wlr-randr # Output management
  ];
}
