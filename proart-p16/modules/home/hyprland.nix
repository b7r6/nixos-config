# Hyprland configuration with Hy3 tiling optimized for ASUS ProArt P16
{ config, lib, pkgs, flake, ... }:

let
  inherit (flake) inputs;
  
  # Monitor management script for handling external displays and lid switch events
  monitor-handler = pkgs.writeShellScriptBin "monitor-handler" ''
    #!/usr/bin/env bash
    
    # Script to handle monitor configurations and lid switch events
    # This is optimized for ASUS ProArt P16 with 3840x2400 display
    
    # Monitor configuration constants
    LAPTOP_MONITOR="eDP-1"
    LAPTOP_RESOLUTION="3840x2400@60"
    LAPTOP_SCALE="1.5"
    
    # Function to check if the laptop lid is closed
    function is_lid_closed() {
      grep -q closed /proc/acpi/button/lid/*/state
      return $?
    }
    
    # Function to detect connected monitors
    function get_connected_monitors() {
      hyprctl monitors -j | jq -r '.[] | select(.name != "HEADLESS-1") | .name' | sort
    }
    
    # Function to check if specified monitor is connected
    function is_monitor_connected() {
      local monitor="$1"
      hyprctl monitors -j | jq -r '.[] | .name' | grep -q "^$monitor$"
      return $?
    }
    
    # Configure all connected monitors optimally
    function configure_monitors() {
      # Get the list of all connected monitors
      local all_monitors=$(get_connected_monitors)
      local external_monitors=$(echo "$all_monitors" | grep -v "$LAPTOP_MONITOR" || true)
      local lid_state=$(is_lid_closed && echo "closed" || echo "open")
      
      # Remove all existing monitor rules
      hyprctl keyword monitor "eDP-1,disable"
      
      # If there are external monitors
      if [[ -n "$external_monitors" ]]; then
        local x_pos=0
        local primary_set=0
        
        # Configure external monitors first
        while IFS= read -r monitor; do
          # Get monitor properties
          local monitor_info=$(hyprctl monitors -j | jq -r ".[] | select(.name == \"$monitor\")")
          local width=$(echo "$monitor_info" | jq -r '.width')
          local height=$(echo "$monitor_info" | jq -r '.height')
          local refresh=$(echo "$monitor_info" | jq -r '.refreshRate')
          local description=$(echo "$monitor_info" | jq -r '.description' | sed 's/ /_/g')
          
          # Round refresh rate to handle fractional rates
          refresh=$(printf "%.0f" $refresh)
          
          # Set monitor configuration
          if [[ $primary_set -eq 0 ]]; then
            # Make the first external monitor primary
            hyprctl keyword monitor "$monitor,$width"x"$height@$refresh,$x_pos"x"0,1,bitdepth,10,vrr,1"
            primary_set=1
          else
            hyprctl keyword monitor "$monitor,$width"x"$height@$refresh,$x_pos"x"0,1,bitdepth,10,vrr,1"
          fi
          
          # Move position for next monitor
          x_pos=$((x_pos + width))
        done <<< "$external_monitors"
        
        # Only enable the laptop display if the lid is open
        if [[ "$lid_state" == "open" ]]; then
          hyprctl keyword monitor "$LAPTOP_MONITOR,$LAPTOP_RESOLUTION,$x_pos"x"0,$LAPTOP_SCALE,bitdepth,10"
        fi
      else
        # No external monitors, just use the laptop display
        hyprctl keyword monitor "$LAPTOP_MONITOR,$LAPTOP_RESOLUTION,0x0,$LAPTOP_SCALE,bitdepth,10"
      fi
      
      # Ensure workspaces are properly mapped
      remap_workspaces
    }
    
    # Remap workspaces to appropriate monitors
    function remap_workspaces() {
      local all_monitors=$(get_connected_monitors)
      local count=$(echo "$all_monitors" | wc -l)
      
      # Ensure workspace 1 is on first monitor
      hyprctl dispatch workspace 1
      
      # If we have more than one monitor, distribute workspaces
      if [[ $count -gt 1 ]]; then
        local idx=1
        while IFS= read -r monitor; do
          # Map workspaces based on monitor position
          if [[ $idx -eq 1 ]]; then
            # First monitor: workspaces 1-5
            hyprctl keyword workspace 1,monitor:"$monitor"
            hyprctl keyword workspace 2,monitor:"$monitor"
            hyprctl keyword workspace 3,monitor:"$monitor"
            hyprctl keyword workspace 4,monitor:"$monitor"
            hyprctl keyword workspace 5,monitor:"$monitor"
          elif [[ $idx -eq 2 ]]; then
            # Second monitor: workspaces 6-10
            hyprctl keyword workspace 6,monitor:"$monitor"
            hyprctl keyword workspace 7,monitor:"$monitor"
            hyprctl keyword workspace 8,monitor:"$monitor"
            hyprctl keyword workspace 9,monitor:"$monitor"
            hyprctl keyword workspace 10,monitor:"$monitor"
            # Move to first workspace on this monitor
            hyprctl dispatch workspace 6
          elif [[ $idx -eq 3 ]]; then
            # Third monitor (if any): special workspaces
            hyprctl keyword workspace 11,monitor:"$monitor"
            hyprctl keyword workspace 12,monitor:"$monitor"
            hyprctl keyword workspace 13,monitor:"$monitor"
            hyprctl keyword workspace 14,monitor:"$monitor"
            hyprctl keyword workspace 15,monitor:"$monitor"
            # Move to first workspace on this monitor
            hyprctl dispatch workspace 11
          fi
          idx=$((idx + 1))
        done <<< "$all_monitors"
      fi
    }
    
    # Monitor added/removed event handler
    function handle_monitor_change() {
      echo "Monitor change detected, reconfiguring..."
      sleep 1  # Give the system a moment to register the changes
      configure_monitors
    }
    
    # Handle lid switch event
    function handle_lid_switch() {
      local lid_state=$(is_lid_closed && echo "closed" || echo "open")
      echo "Lid $lid_state event detected"
      
      # Get list of external monitors
      local all_monitors=$(get_connected_monitors)
      local external_monitors=$(echo "$all_monitors" | grep -v "$LAPTOP_MONITOR" || true)
      
      if [[ -n "$external_monitors" ]]; then
        # External monitors are connected
        if [[ "$lid_state" == "closed" ]]; then
          # Lid closed - disable internal display
          hyprctl keyword monitor "eDP-1,disable"
        else
          # Lid opened - re-configure all monitors
          configure_monitors
        fi
      else
        # No external monitors
        if [[ "$lid_state" == "closed" ]]; then
          # Lid closed with no external monitors - lock and suspend
          swaylock -f &
          sleep 1
          systemctl suspend
        else
          # Lid opened - just ensure the internal display is on
          configure_monitors
        fi
      fi
    }
    
    # Watch for lid switch events (requires inotify-tools package)
    function watch_lid_switch() {
      # Initial lid state check
      handle_lid_switch
      
      # Watch for changes to lid state
      while true; do
        inotifywait -qq -e modify /proc/acpi/button/lid/*/state
        handle_lid_switch
      done
    }
    
    # Watch for monitor changes
    function watch_monitors() {
      # Initial configuration
      configure_monitors
      
      # Watch for monitor change events from Hyprland
      socat -u UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -r line; do
        if [[ "$line" == monitoradded* ]] || [[ "$line" == monitorremoved* ]]; then
          handle_monitor_change
        fi
      done
    }
    
    # Main function
    case "$1" in
      "configure")
        configure_monitors
        ;;
      "watch-monitors")
        watch_monitors
        ;;
      "watch-lid")
        watch_lid_switch
        ;;
      "lid-state")
        is_lid_closed && echo "closed" || echo "open"
        ;;
      "handle-lid")
        handle_lid_switch
        ;;
      *)
        echo "Usage: $0 [configure|watch-monitors|watch-lid|lid-state|handle-lid]"
        echo "  configure: Set up monitors according to current state"
        echo "  watch-monitors: Watch for monitor connection/disconnection events"
        echo "  watch-lid: Watch for lid close/open events"
        echo "  lid-state: Show current lid state (open/closed)"
        echo "  handle-lid: Handle the current lid state"
        exit 1
        ;;
    esac
  '';
in
{
  options.wayland.hyprland = {
    enable = lib.mkEnableOption "Enable Hyprland with Hy3 tiling";
  };

  config = lib.mkIf config.wayland.hyprland.enable {
    # Import Hyprland module from upstream
    wayland.windowManager.hyprland = {
      enable = true;
      package = inputs.hyprland.packages.${pkgs.system}.hyprland;
      xwayland.enable = true;
      
      # Use Hy3 plugin for better tiling
      plugins = [
        inputs.hy3.packages.${pkgs.system}.hy3
      ];
      
      # These settings are optimized for ASUS ProArt P16 with 4K display
      extraConfig = ''
        # Set environment variables for proper Nvidia+AMD operation
        env = LIBVA_DRIVER_NAME,radeonsi
        env = WLR_NO_HARDWARE_CURSORS,1
        
        # IMPORTANT - Correctly order the cards (AMD first, then NVIDIA)
        # Use 'ls -la /dev/dri/by-path' to find correct card order
        env = WLR_DRM_DEVICES,/dev/dri/card0:/dev/dri/card1
        
        # Use Wayland where possible and fix scaling
        env = GBM_BACKEND,radeonsi
        env = __GLX_VENDOR_LIBRARY_NAME,amd
        env = MOZ_ENABLE_WAYLAND,1
        env = XDG_SESSION_TYPE,wayland
        env = QT_WAYLAND_DISABLE_WINDOWDECORATION,1
        env = QT_QPA_PLATFORM,wayland
        env = GDK_BACKEND,wayland,x11
        
        # Force X11 apps to use AMD GPU
        env = DRI_PRIME=1
        
        # Initial monitor configuration
        # Start with a simple configuration first to ensure display works
        monitor = eDP-1,3840x2400@60,0x0,1.5,bitdepth,10
        
        # Only run monitor-handler after initial display is working
        exec-once = sleep 5 && monitor-handler configure
        exec-once = sleep 6 && monitor-handler watch-monitors
        exec-once = sleep 7 && monitor-handler watch-lid
        
        # Configure lid switch behavior
        bindl = , switch:off:Lid Switch, exec, monitor-handler handle-lid
        bindl = , switch:on:Lid Switch, exec, monitor-handler handle-lid
      '';
      
      settings = {
        # General settings
        general = {
          gaps_in = 5;
          gaps_out = 10;
          border_size = 2;
          "col.active_border" = "rgba(33ccffee)";
          "col.inactive_border" = "rgba(595959aa)";
          layout = "dwindle";
          allow_tearing = false;
          resize_on_border = true;
        };
        
        # Better performance with NVIDIA GPU
        decoration = {
          rounding = 10;
          blur = {
            enabled = false;  # Disable blur initially for better performance
            size = 8;
            passes = 2;
            new_optimizations = true;
            xray = true;
            ignore_opacity = true;
          };
          shadow_range = 20;
          shadow_render_power = 2;
          "col.shadow" = "rgba(00000099)";
        };
        
        # Improved animations that work well with hybrid AMD/NVIDIA
        animations = {
          enabled = true;
          bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
          animation = [
            "windows, 1, 5, myBezier"
            "windowsOut, 1, 5, default, popin 80%"
            "border, 1, 8, default"
            "fade, 1, 5, default"
            "workspaces, 1, 5, default"
          ];
        };
        
        # Touch and input configurations optimized for ProArt P16
        input = {
          kb_layout = "us";
          kb_variant = "";
          kb_options = "";
          follow_mouse = 1;
          touchpad = {
            natural_scroll = true;
            disable_while_typing = true;
            tap-to-click = true;
            drag_lock = true;
            clickfinger_behavior = true;
          };
          sensitivity = 0;
          accel_profile = "flat";
        };
        
        # Optimized for Hy3 tiling
        plugin = {
          hy3 = {
            tabs = {
              height = 20;
              padding = 8;
              render_text = true;
              text_font = "Berkeley Mono";
              text_height = 12;
              text_padding = 4;
              col.active = "rgba(33ccffee)";
              col.urgent = "rgba(ee2233ee)";
              col.inactive = "rgba(595959aa)";
            };
            autotile = {
              enable = true;
              trigger_width = 800;
              trigger_height = 500;
            };
          };
        };
        
        # Window rules
        windowrulev2 = [
          "float,class:^(pavucontrol)$"
          "float,class:^(nm-connection-editor)$"
          "float,title:^(Picture-in-Picture)$"
          "float,class:^(thunar)$,title:^(File Operation)$"
          "float,class:^(firefox)$,title:^(Library)$"
          "workspace 1,class:^(firefox)$"
          "workspace 2,class:^(wezterm)$"
          "workspace 3,class:^(emacs)$"
        ];
        
        # Main mod key (SUPER/WIN key)
        "$mainMod" = "SUPER";
        
        # Add keybinding to toggle monitor config for testing
        bind = [
          # Essential keybindings
          "$mainMod, Return, exec, wezterm"
          "$mainMod, Q, killactive,"
          "$mainMod, M, exit,"
          "$mainMod, E, exec, thunar"
          "$mainMod, V, togglefloating,"
          "$mainMod, SPACE, exec, wofi --show drun"
          "$mainMod, P, pseudo,"
          "$mainMod, J, togglesplit,"
          "$mainMod, F, fullscreen, 1"
          "$mainMod SHIFT, F, fullscreen, 0"
          
          # Manually reconfigure monitors (for testing)
          "$mainMod SHIFT, M, exec, monitor-handler configure"
          
          # Move focus with mainMod + arrow keys
          "$mainMod, left, movefocus, l"
          "$mainMod, right, movefocus, r"
          "$mainMod, up, movefocus, u"
          "$mainMod, down, movefocus, d"
          
          # Move active window with mainMod + SHIFT + arrow keys
          "$mainMod SHIFT, left, movewindow, l"
          "$mainMod SHIFT, right, movewindow, r"
          "$mainMod SHIFT, up, movewindow, u"
          "$mainMod SHIFT, down, movewindow, d"
          
          # Switch workspaces
          "$mainMod, 1, workspace, 1"
          "$mainMod, 2, workspace, 2"
          "$mainMod, 3, workspace, 3"
          "$mainMod, 4, workspace, 4"
          "$mainMod, 5, workspace, 5"
          "$mainMod, 6, workspace, 6"
          "$mainMod, 7, workspace, 7"
          "$mainMod, 8, workspace, 8"
          "$mainMod, 9, workspace, 9"
          "$mainMod, 0, workspace, 10"
          
          # Move active window to a workspace
          "$mainMod SHIFT, 1, movetoworkspace, 1"
          "$mainMod SHIFT, 2, movetoworkspace, 2"
          "$mainMod SHIFT, 3, movetoworkspace, 3"
          "$mainMod SHIFT, 4, movetoworkspace, 4"
          "$mainMod SHIFT, 5, movetoworkspace, 5"
          "$mainMod SHIFT, 6, movetoworkspace, 6"
          "$mainMod SHIFT, 7, movetoworkspace, 7"
          "$mainMod SHIFT, 8, movetoworkspace, 8"
          "$mainMod SHIFT, 9, movetoworkspace, 9"
          "$mainMod SHIFT, 0, movetoworkspace, 10"
          
          # Move active window to a workspace with mainMod + CTRL + [0-9]
          "$mainMod CTRL, 1, movetoworkspacesilent, 1"
          "$mainMod CTRL, 2, movetoworkspacesilent, 2"
          "$mainMod CTRL, 3, movetoworkspacesilent, 3"
          "$mainMod CTRL, 4, movetoworkspacesilent, 4"
          "$mainMod CTRL, 5, movetoworkspacesilent, 5"
          "$mainMod CTRL, 6, movetoworkspacesilent, 6"
          "$mainMod CTRL, 7, movetoworkspacesilent, 7"
          "$mainMod CTRL, 8, movetoworkspacesilent, 8"
          "$mainMod CTRL, 9, movetoworkspacesilent, 9"
          "$mainMod CTRL, 0, movetoworkspacesilent, 10"
          
          # Scroll through existing workspaces with mainMod + scroll
          "$mainMod, mouse_down, workspace, e+1"
          "$mainMod, mouse_up, workspace, e-1"
          
          # Move/resize windows with mainMod + LMB/RMB and dragging
          "$mainMod, mouse:272, movewindow"
          "$mainMod, mouse:273, resizewindow"
          
          # Quick lock screen
          "$mainMod ALT, L, exec, swaylock -f"
          
          # Volume control
          ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"
          ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
          ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          
          # Brightness control
          ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
          ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
          
          # Media control
          ", XF86AudioPlay, exec, playerctl play-pause"
          ", XF86AudioNext, exec, playerctl next"
          ", XF86AudioPrev, exec, playerctl previous"
        ];
        
        bindm = [
          "$mainMod, mouse:272, movewindow"
          "$mainMod, mouse:273, resizewindow"
        ];

        # Dwindle layout configuration
        dwindle = {
          pseudotile = true;
          preserve_split = true;
          no_gaps_when_only = false;
          force_split = 2;  # Split right by default
        };
        
        # Gestures
        gestures = {
          workspace_swipe = true;
          workspace_swipe_fingers = 3;
          workspace_swipe_distance = 300;
          workspace_swipe_invert = false;
          workspace_swipe_min_speed_to_force = 30;
          workspace_swipe_create_new = false;
        };
        
        # Misc settings
        misc = {
          disable_hyprland_logo = true;
          disable_splash_rendering = true;
          mouse_move_enables_dpms = true;
          key_press_enables_dpms = true;
          enable_swallow = true;
          swallow_regex = "^(Alacritty|wezterm)$";
          
          # Add VRAM usage optimization
          vram_reduce = true;
        };
        
        # Startup applications
        exec-once = [
          "waybar"
          "dunst"                            # Notification daemon
          "wl-paste --type text --watch cliphist store"  # Clipboard manager
          "wl-paste --type image --watch cliphist store" # Image clipboard
          "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator" # Network manager
          "swayidle -w timeout 300 'swaylock -f' timeout 600 'hyprctl dispatch dpms off' resume 'hyprctl dispatch dpms on'" # Screen locking
        ];
      };
    };
    
    # Essential packages for Hyprland environment
    home.packages = with pkgs; [
      # Custom monitor handler script
      monitor-handler
      
      # Required for monitor-handler
      socat
      jq
      inotify-tools
      
      # Waybar for status bar with improved support for AMD/NVIDIA
      waybar
      
      # Notifications
      libnotify
      dunst
      
      # Application launcher
      wofi
      
      # Screen tools optimized for Wayland
      wl-clipboard
      cliphist
      grim
      slurp
      
      # Better power management
      auto-cpufreq
      powertop
      
      # GPU tools
      nvtop
      radeontop
      
      # Improved system monitoring
      bottom
      btop
      
      # ASUS tools
      asusctl
      supergfxctl
      
      # Screen locking
      swayidle
      swaylock
      
      # Brightness control
      brightnessctl
      
      # Media controls
      playerctl
      
      # Network management
      networkmanagerapplet
    ];
    
    # Start Hyprland automatically on login
    programs.bash.initExtra = ''
      if [ -z $DISPLAY ] && [ "$(tty)" = "/dev/tty1" ]; then
        # Configure AMD as primary GPU before starting Hyprland
        export DRI_PRIME=1
        export WLR_DRM_DEVICES=/dev/dri/card0:/dev/dri/card1
        exec Hyprland
      fi
    '';
    
    # Configure GTK theming for Wayland
    gtk = {
      enable = true;
      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome.gnome-themes-extra;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
      font = {
        name = "Berkeley Mono";
        size = 11;
      };
    };
    
    # Configure waybar
    programs.waybar = {
      enable = true;
      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 36;
          
          modules-left = ["hyprland/workspaces"];
          modules-center = ["hyprland/window"];
          modules-right = [
            "custom/gpu"
            "temperature"
            "cpu"
            "memory"
            "battery"
            "network"
            "pulseaudio"
            "tray"
            "clock"
          ];
          
          "hyprland/workspaces" = {
            format = "{name}";
            on-scroll-up = "hyprctl dispatch workspace e+1";
            on-scroll-down = "hyprctl dispatch workspace e-1";
            on-click = "activate";
          };
          
          "hyprland/window" = {
            max-length = 80;
            separate-outputs = true;
          };
          
          "custom/gpu" = {
            format = "GPU: {}";
            exec = "supergfxctl -g | tr -d '\\n'";
            interval = 5;
            on-click = "supergfxctl -s Hybrid";
            tooltip = true;
            tooltip-format = "Click to toggle GPU mode";
          };
          
          "temperature" = {
            format = "{temperatureC}°C ";
            critical-threshold = 80;
            tooltip = true;
          };
          
          "cpu" = {
            format = "CPU: {usage}%";
            interval = 1;
            tooltip = true;
          };
          
          "memory" = {
            format = "MEM: {percentage}%";
            tooltip-format = "{used:0.1f} GiB / {total:0.1f} GiB";
            interval = 2;
          };
          
          "battery" = {
            format = "{icon} {capacity}%";
            format-charging = "⚡ {capacity}%";
            format-alt = "{icon} {time}";
            format-icons = ["" "" "" "" ""];
            interval = 30;
            states = {
              warning = 30;
              critical = 15;
            };
            tooltip = true;
          };
          
          "network" = {
            format-wifi = "WiFi: {signalStrength}%";
            format-ethernet = "ETH: Connected";
            format-disconnected = "NET: Disconnected";
            tooltip-format = "{ifname}: {ipaddr}/{cidr}";
          };
          
          "pulseaudio" = {
            format = "{icon} {volume}%";
            format-muted = "🔇 Muted";
            format-icons = {
              default = ["" "" ""];
            };
            scroll-step = 5;
            on-click = "pavucontrol";
          };
          
          "tray" = {
            icon-size = 18;
            spacing = 8;
          };
          
          "clock" = {
            format = "{:%I:%M %p}";
            format-alt = "{:%Y-%m-%d %a}";
            tooltip-format = "{:%Y-%m-%d | %I:%M %p}";
            on-click = "waybar-calendar";
          };
        };
      };
      
      style = ''
        * {
          font-family: "Berkeley Mono", monospace;
          font-size: 13px;
        }
        
        window#waybar {
          background-color: rgba(0, 0, 0, 0.8);
          color: #ffffff;
          transition-property: background-color;
          transition-duration: .5s;
        }
        
        window#waybar.hidden {
          opacity: 0.2;
        }
        
        #workspaces button {
          padding: 0 6px;
          background-color: transparent;
          color: #ffffff;
          border-bottom: 3px solid transparent;
        }
        
        #workspaces button:hover {
          background: rgba(0, 0, 0, 0.2);
          box-shadow: inherit;
          border-bottom: 3px solid white;
        }
        
        #workspaces button.active {
          background-color: rgba(33, 150, 243, 0.4);
          border-bottom: 3px solid white;
        }
        
        #workspaces button.urgent {
          background-color: #eb4d4b;
        }
        
        #mode {
          background-color: #64727D;
          border-bottom: 3px solid white;
        }
        
        #clock,
        #battery,
        #cpu,
        #memory,
        #custom-media,
        #tray,
        #mode,
        #temperature,
        #custom-gpu,
        #backlight,
        #network,
        #pulseaudio {
          padding: 0 10px;
          margin: 0 4px;
          color: white;
        }
      '';
    };
  };
} 