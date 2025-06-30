{
  flake,
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.wayland.hyprland;
  inherit (flake) inputs;

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
      monitor = [
        "eDP-1,3840x2400@60.00000,0x0,2.5"
        # "desc:LG Electronics LG ULTRAGEAR+,3840x2160x120hz,0x0,1.5"
      ];

      # ===== Persistent Workspace Assignment =====
      workspace = [
        "1, monitor:eDP-1, default:true, persistent:true"
        "2, monitor:eDP-1, persistent:true"
        "3, monitor:eDP-1, persistent:true"
        "4, monitor:eDP-1, persistent:true"
        "5, monitor:eDP-1, persistent:true"
        "6, monitor:eDP-1, persistent:true"
        "special:scratchpad, on-created-empty:wezterm"
      ];

      exec-once = [
        "blueman-applet"
        "flameshot"
        "hyprpaper"
        "mako"
        "nm-tray"
        "tailscale-systray"
      ];

      general = {
        border_size = 2;
        gaps_in = 2;
        gaps_out = 2;
        layout = "hy3";
        resize_on_border = true;

        "col.active_border" = lib.mkForce "rgba(${base0D}ee) rgba(${base0E}ee) 45deg";
        "col.inactive_border" = lib.mkForce "rgba(${base02}aa)";
      };

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

        active_opacity = 1.0;
        inactive_opacity = 0.95;
        fullscreen_opacity = 1.0;
      };

      animations = {
        enabled = true;

        bezier = [
          "easeOutQuint, 0.22, 1, 0.36, 1"
          "easeInQuint, 0.64, 0, 0.78, 0"
        ];

        animation = [
          "windows, 1, 3, easeOutQuint"
          "windowsOut, 1, 3, easeInQuint, popin 80%"
          "border, 1, 3, easeOutQuint"
          "fade, 1, 3, easeOutQuint"
          "workspaces, 1, 3, easeOutQuint"
          "specialWorkspace, 1, 3, easeOutQuint, slidevert"
        ];
      };

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

      gestures = {
        workspace_swipe = true;
        workspace_swipe_fingers = 3;
        workspace_swipe_distance = 300;
        workspace_swipe_invert = false;
        workspace_swipe_create_new = false;
      };

      misc = {
        force_default_wallpaper = 0;
        animate_mouse_windowdragging = false;
        animate_manual_resizes = false;
        enable_swallow = true;
        swallow_regex = "^(wezterm|ghostty|alacritty)$";
        focus_on_activate = true;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
      };

      plugin.hy3 = {
        tabs = {
          height = 16;
          padding = 0;
          from_top = true;
          rounding = 0; # No rounding
          render_text = true;

          "col.active" = "rgba(${base0D}ee)";
          "col.inactive" = "rgba(${base02}aa)";
          "col.text.active" = "rgba(${base05}ee)";
          "col.text.inactive" = "rgba(${base04}aa)";

          border_width = 1;
        };

        autotile = {
          enable = true;
          trigger_width = 800;
          trigger_height = 500;
          main_ratio = 0.5;
        };
      };

      "$mod" = "SUPER";
      "$alt" = "ALT";

      bind = [
        # Core bindings
        "$mod, Return, exec, wezterm"
        "$mod, Space, exec, wofi --show drun"
        "$mod, E, exec, nemo"
        "$mod, W, exec, firefox"
        "$mod, BackSpace, killactive"
        "$mod SHIFT, BackSpace, exit"

        # Window states
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, fullscreen, 1"
        "$mod, D, togglefloating"
        "$mod, P, pin"

        # Layout controls with hy3
        "$mod, V, hy3:makegroup, v"
        "$mod, B, hy3:makegroup, h"
        "$mod, T, hy3:makegroup, tab"
        "$mod, G, hy3:changegroup, toggletab"
        "$mod, R, hy3:changefocus, raise"
        "$mod SHIFT, G, hy3:changegroup, opposite"

        # Scratchpad (special workspace)
        "$mod, S, togglespecialworkspace, scratchpad"
        "$mod SHIFT, S, movetoworkspace, special:scratchpad"

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
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod, 0, workspace, 10"

        # Move windows to workspaces
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, 0, movetoworkspace, 10"

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

        # Screenshots
        "$mod, Print, exec, grimblast copy area"
        "$mod SHIFT, Print, exec, grimblast save area ~/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png"
        "$mod $alt, Print, exec, grimblast copy screen"
        "$mod $alt SHIFT, Print, exec, grimblast save screen ~/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png"

        # Media controls
        ", XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%"
        ", XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%"
        ", XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"

        # Brightness
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

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 24;
        spacing = 0;

        modules-left = [
          "hyprland/workspaces"
          "hyprland/window"
        ];

        modules-center = [ "clock" ];

        modules-right = [
          "cpu"
          "memory"
          "battery"
          "network"
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

        "hyprland/window" = {
          format = "{}";
          max-length = 50;
          separate-outputs = true;
        };

        "clock" = {
          format = "{:%H:%M}";
          format-alt = "{:%Y-%m-%d}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "year";
            mode-mon-col = 3;
            weeks-pos = "right";
            on-scroll = 1;
            on-click-right = "mode";
            format = {
              months = "<span color='#${colors.base0D}'><b>{}</b></span>";
              days = "<span color='#${colors.base05}'><b>{}</b></span>";
              weeks = "<span color='#${colors.base04}'><b>W{}</b></span>";
              weekdays = "<span color='#${colors.base0A}'><b>{}</b></span>";
              today = "<span color='#${colors.base08}'><b><u>{}</u></b></span>";
            };
          };
        };

        "cpu" = {
          format = "CPU {usage}%";
          tooltip = true;
          interval = 2;
        };

        "memory" = {
          format = "MEM {used:0.1f}G";
          tooltip-format = "Memory: {used:0.1f}G / {total:0.1f}G\nSwap: {swapUsed:0.1f}G / {swapTotal:0.1f}G";
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
          tooltip-format = "{timeTo}, {capacity}%\n{power}W";
        };

        "network" = {
          format-wifi = "WIFI {signalStrength}%";
          format-ethernet = "ETH";
          format-linked = "ETH (No IP)";
          format-disconnected = "OFFLINE";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}\n{essid}";
          max-length = 50;
          interval = 5;
        };

        "pulseaudio" = {
          format = "VOL {volume}%";
          format-muted = "MUTED";
          format-bluetooth = "BT {volume}%";
          format-bluetooth-muted = "BT MUTED";
          on-click = "pavucontrol";
          on-click-right = "pactl set-sink-mute @DEFAULT_SINK@ toggle";
        };

        "tray" = {
          icon-size = 14;
          spacing = 4;
        };
      };
    };

    style = ''
      * {
        font-family: "${config.stylix.fonts.monospace.name}", monospace;
        font-size: ${toString config.stylix.fonts.sizes.applications}px;
        border-radius: 0px;
        border: none;
        min-height: 0;
      }

      window#waybar {
        background-color: #${colors.base00};
        color: #${colors.base05};
        border-bottom: 1px solid #${colors.base02};
      }

      #workspaces button {
        padding: 0 6px;
        background-color: transparent;
        color: #${colors.base05};
        border-bottom: 2px solid transparent;
      }

      #workspaces button:hover {
        background: #${colors.base01};
        box-shadow: inherit;
        border-bottom: 2px solid #${colors.base04};
      }

      #workspaces button.active {
        background-color: #${colors.base02};
        border-bottom: 2px solid #${colors.base0D};
        color: #${colors.base0D};
      }

      #workspaces button.urgent {
        background-color: #${colors.base08};
        color: #${colors.base00};
      }

      #clock,
      #battery,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #tray,
      #window {
        padding: 0 8px;
        color: #${colors.base05};
      }

      #window {
        color: #${colors.base04};
      }

      #battery.charging {
        color: #${colors.base0B};
      }

      #battery.warning:not(.charging) {
        color: #${colors.base0A};
      }

      #battery.critical:not(.charging) {
        background-color: #${colors.base08};
        color: #${colors.base00};
        animation-name: blink;
        animation-duration: 0.5s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
      }

      #network.disconnected {
        color: #${colors.base08};
      }

      #pulseaudio.muted {
        color: #${colors.base04};
      }

      @keyframes blink {
        to {
          background-color: #${colors.base00};
          color: #${colors.base08};
        }
      }

      tooltip {
        background: #${colors.base00};
        border: 1px solid #${colors.base0D};
        border-radius: 0px;
      }

      tooltip label {
        color: #${colors.base05};
      }
    '';
  };

  services.mako = {
    enable = true;

    settings = {
      # General settings
      # font = "${config.stylix.fonts.monospace.name} ${toString config.stylix.fonts.sizes.applications}";
      # background-color = lib.mkForce "#${colors.base00}";
      text-color = "#${colors.base05}";
      border-color = "#${colors.base0D}";
      border-size = 1;
      border-radius = 0;
      padding = "8";
      default-timeout = 5000;
      layer = "overlay";
      progress-color = "over #${colors.base02}";
    };

    extraConfig = ''
      [urgency=low]
      border-color=#${colors.base0D}

      [urgency=normal]
      border-color=#${colors.base0D}

      [urgency=high]
      border-color=#${colors.base08}
      background-color=#${colors.base00}
      text-color=#${colors.base08}
      default-timeout=0
    '';
  };

  programs.wofi = {
    enable = true;
    settings = {
      width = 600;
      height = 400;
      location = "center";
      show = "drun";
      prompt = "Search...";
      filter_rate = 100;
      allow_markup = true;
      no_actions = true;
      halign = "fill";
      orientation = "vertical";
      content_halign = "fill";
      insensitive = true;
      allow_images = true;
      image_size = 32;
      gtk_dark = true;
    };

    style = ''
      window {
        margin: 0px;
        background-color: #${colors.base00};
        border: 2px solid #${colors.base0D};
        border-radius: 0px;
      }

      #input {
        margin: 8px;
        padding: 8px;
        border: 1px solid #${colors.base02};
        border-radius: 0px;
        color: #${colors.base05};
        background-color: #${colors.base01};
        font-size: ${toString config.stylix.fonts.sizes.applications}px;
      }

      #inner-box {
        margin: 8px;
        background-color: #${colors.base00};
        border-radius: 0px;
      }

      #outer-box {
        margin: 0px;
        padding: 0px;
        background-color: #${colors.base00};
        border-radius: 0px;
      }

      #scroll {
        margin: 0px;
        background-color: #${colors.base00};
      }

      #text {
        margin: 2px;
        padding: 4px;
        color: #${colors.base05};
      }

      #entry {
        padding: 4px;
        margin: 2px;
      }

      #entry:selected {
        background-color: #${colors.base02};
        border: 1px solid #${colors.base0D};
      }

      #text:selected {
        color: #${colors.base0D};
        font-weight: bold;
      }
    '';
  };

  home.packages = with pkgs; [
    blueman
    brightnessctl
    flameshot
    grim
    grimblast
    hyprpaper
    hyprpicker # Color picker
    jq
    libnotify
    mako
    nm-tray
    pamixer
    pavucontrol
    playerctl
    slurp
    swappy
    tailscale-systray
    wev
    wl-clipboard
    wlr-randr
    wofi
  ];
}
