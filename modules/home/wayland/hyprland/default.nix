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
  base00 = lib.removePrefix "#" colors.base00;
  base01 = lib.removePrefix "#" colors.base01;
  base02 = lib.removePrefix "#" colors.base02;
  base04 = lib.removePrefix "#" colors.base04;
  base05 = lib.removePrefix "#" colors.base05;
  base08 = lib.removePrefix "#" colors.base08;
  base0A = lib.removePrefix "#" colors.base0A;
  base0B = lib.removePrefix "#" colors.base0B;
  base0D = lib.removePrefix "#" colors.base0D;
  base0E = lib.removePrefix "#" colors.base0E;
in
{
  imports = [ inputs.hyprland.homeManagerModules.default ];

  wayland.windowManager.hyprland = {
    inherit (cfg) enable;
    systemd.enable = true;

    plugins = [ inputs.hy3.outputs.packages.${pkgs.system}.hy3 ];

    settings = {
      monitor = [
        "eDP-1,3840x2400@60,0x0,3.0"
      ];

      workspace = [
        # Samsung Display Corp. 0x415D
        "1, monitor:eDP-1, default:true, persistent:true"
        "2, monitor:eDP-1, persistent:true"
        "3, monitor:eDP-1, persistent:true"
        "4, monitor:eDP-1, persistent:true"
        "5, monitor:eDP-1, persistent:true"
        "6, monitor:eDP-1, persistent:true"
      ];

      exec-once = [
        "hyprpaper"
        "waybar" # Explicitly start waybar
        "mako"
        "blueman-applet"
        "nm-applet"
        "tailscale-systray"
      ];

      general = {
        border_size = 2;
        gaps_in = 4;
        gaps_out = 8;
        layout = "hy3";
        resize_on_border = true;

        "col.active_border" = lib.mkForce "rgba(${base0D}ff) rgba(${base0E}ff) 45deg";
        "col.inactive_border" = lib.mkForce "rgba(${base02}66)";
      };

      decoration = {
        rounding = 0;

        blur = {
          enabled = true;
          size = 8;
          passes = 2;
          new_optimizations = true;
          xray = true;
          ignore_opacity = false;
          brightness = 0.8;
          contrast = 1.2;
          noise = 0.01;
        };

        active_opacity = 1.0;
        inactive_opacity = 0.85;
        fullscreen_opacity = 1.0;
      };

      animations = {
        enabled = true;

        bezier = [
          "easeOutQuint, 0.22, 1, 0.36, 1"
          "easeInOutQuint, 0.83, 0, 0.17, 1"
          "easeOutExpo, 0.16, 1, 0.3, 1"
        ];

        animation = [
          "windows, 1, 3, easeOutExpo, popin 80%"
          "windowsOut, 1, 3, easeOutExpo, popin 80%"
          "border, 1, 5, easeOutQuint"
          "fade, 1, 3, easeInOutQuint"
          "workspaces, 1, 3, easeOutExpo, slide"
          "specialWorkspace, 1, 3, easeOutExpo, slidevert"
        ];
      };

      input = {
        kb_layout = "us";
        follow_mouse = 1;
        sensitivity = 0;
        accel_profile = "flat";
        mouse_refocus = false;

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
        swallow_regex = "^(wezterm|ghostty|alacritty|foot|kitty)$";
        focus_on_activate = true;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        vfr = true;
        vrr = 1;
        mouse_move_enables_dpms = true;
        key_press_enables_dpms = true;
      };

      plugin.hy3 = {
        tabs = {
          height = 20;
          padding = 4;
          from_top = true;
          rounding = 0;
          render_text = true;
          text_font = config.stylix.fonts.monospace.name;
          text_height = 10;

          "col.active" = "rgba(${base0D}ff)";
          "col.inactive" = "rgba(${base01}ff)";
          "col.text.active" = "rgba(${base00}ff)";
          "col.text.inactive" = "rgba(${base04}ff)";
        };

        autotile = {
          enable = true;
          trigger_width = 800;
          trigger_height = 500;
        };
      };

      "$mod" = "SUPER";
      "$alt" = "ALT";

      bind = [
        # Core bindings
        "$mod, Return, exec, wezterm"
        "$mod SHIFT, Return, exec, [float] wezterm"
        "$mod, Space, exec, wofi --show drun"
        "$mod SHIFT, Space, exec, wofi --show run"
        "$mod, E, exec, nemo"
        "$mod, W, exec, firefox"
        "$mod, BackSpace, killactive"
        "$mod SHIFT, BackSpace, exit"

        # Window states
        "$mod, F, fullscreen, 0"
        "$mod SHIFT, F, fullscreen, 1"
        "$mod, D, togglefloating"
        "$mod, P, pin"
        "$mod, C, centerwindow"

        # Layout controls with hy3
        "$mod, V, hy3:makegroup, v"
        "$mod, B, hy3:makegroup, h"
        "$mod, T, hy3:makegroup, tab"
        "$mod, G, hy3:changegroup, toggletab"
        "$mod, R, hy3:changefocus, raise"
        "$mod SHIFT, G, hy3:changegroup, opposite"

        # Monitor navigation
        "$mod, comma, focusmonitor, -1"
        "$mod, period, focusmonitor, +1"

        # Move windows between monitors
        "$mod SHIFT, comma, movewindow, mon:-1"
        "$mod SHIFT, period, movewindow, mon:+1"

        # Workspace switching - per monitor
        "$mod, Tab, workspace, m+1"
        "$mod SHIFT, Tab, workspace, m-1"

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
        "$mod $alt, H, resizeactive, -30 0"
        "$mod $alt, L, resizeactive, 30 0"
        "$mod $alt, K, resizeactive, 0 -30"
        "$mod $alt, J, resizeactive, 0 30"

        # Screenshots
        "$mod, S, exec, grimblast copy area"
        "$mod SHIFT, S, exec, grimblast save area ~/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png"
        "$mod $alt, S, exec, grimblast copy screen"
        "$mod $alt SHIFT, S, exec, grimblast save screen ~/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png"

        # Media controls
        ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
        ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"

        # Brightness
        ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"

        # Lock screen
        "$mod, Escape, exec, swaylock"
      ];

      # Mouse bindings
      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
        "$mod SHIFT, mouse:272, resizewindow"
      ];

      # Window rules for better behavior
      windowrulev2 = [
        "workspace 1, class:^(firefox)$"
        "workspace 2, class:^(Code|code-url-handler)$"
        "workspace 9, class:^(discord|Discord)$"
        "workspace 10, class:^(Spotify|spotify)$"

        # Float specific windows
        "float, class:^(pavucontrol)$"
        "float, class:^(nm-connection-editor)$"
        "float, class:^(.blueman-manager-wrapped)$"
        "float, title:^(Picture-in-Picture)$"

        # PiP rules
        "float, title:^(Picture-in-Picture)$"
        "pin, title:^(Picture-in-Picture)$"
        "size 560 315, title:^(Picture-in-Picture)$"
        "move 100%-576 100%-331, title:^(Picture-in-Picture)$"
      ];
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;

    settings = {
      # mainBar = {
      #     layer = "top";
      #     position = "top";
      #     height = 26;
      #     spacing = 0;
      #     output = "*"; # Show on all monitors

      #     modules-left = [
      #       "hyprland/workspaces"
      #       "hyprland/submap"
      #       "hyprland/window"
      #     ];

      #     modules-center = [ "clock" ];

      #     modules-right = [
      #       "cpu"
      #       "memory"
      #       "temperature"
      #       "battery"
      #       "network"
      #       "pulseaudio"
      #       "tray"
      #     ];

      #     "hyprland/workspaces" = {
      #       format = "{name}";
      #       on-click = "activate";
      #       sort-by-number = true;
      #       all-outputs = false;
      #       active-only = false;
      #       format-icons = {
      #         urgent = "";
      #         focused = "";
      #         default = "";
      #       };
      #     };

      #     "hyprland/window" = {
      #       format = "{}";
      #       max-length = 50;
      #       separate-outputs = true;
      #       rewrite = {
      #         "(.*) — Mozilla Firefox" = "🌐 $1";
      #         "(.*) - Visual Studio Code" = "󰨞 $1";
      #         "(.*) - WezTerm" = " $1";
      #       };
      #     };

      #     "clock" = {
      #       format = "{:%H:%M}";
      #       format-alt = "{:%a %b %d}";
      #       tooltip-format = "<tt><small>{calendar}</small></tt>";
      #       calendar = {
      #         mode = "year";
      #         mode-mon-col = 3;
      #         weeks-pos = "right";
      #         on-scroll = 1;
      #         on-click-right = "mode";
      #         format = {
      #           months = "<span color='#${colors.base0D}'><b>{}</b></span>";
      #           days = "<span color='#${colors.base05}'><b>{}</b></span>";
      #           weeks = "<span color='#${colors.base04}'><b>W{}</b></span>";
      #           weekdays = "<span color='#${colors.base0A}'><b>{}</b></span>";
      #           today = "<span color='#${colors.base08}'><b><u>{}</u></b></span>";
      #         };
      #       };
      #     };

      #     "cpu" = {
      #       format = " {usage}%";
      #       tooltip = true;
      #       interval = 2;
      #       states = {
      #         warning = 70;
      #         critical = 90;
      #       };
      #     };

      #     "memory" = {
      #       format = " {percentage}%";
      #       tooltip-format = "Memory: {used:0.1f}G / {total:0.1f}G\nSwap: {swapUsed:0.1f}G / {swapTotal:0.1f}G";
      #       interval = 2;
      #       states = {
      #         warning = 70;
      #         critical = 90;
      #       };
      #     };

      #     "temperature" = {
      #       critical-threshold = 80;
      #       format = "{icon} {temperatureC}°C";
      #       format-icons = [
      #         ""
      #         ""
      #         ""
      #         ""
      #         ""
      #       ];
      #     };

      #     "battery" = {
      #       states = {
      #         good = 95;
      #         warning = 30;
      #         critical = 15;
      #       };
      #       format = "{icon} {capacity}%";
      #       format-charging = " {capacity}%";
      #       format-plugged = " {capacity}%";
      #       format-icons = [
      #         ""
      #         ""
      #         ""
      #         ""
      #         ""
      #       ];
      #       tooltip-format = "{timeTo}, {capacity}%\n{power}W";
      #     };

      #     "network" = {
      #       format-wifi = " {signalStrength}%";
      #       format-ethernet = "󰈁";
      #       format-linked = "󰈂 No IP";
      #       format-disconnected = "󰈂";
      #       tooltip-format = "{ifname}: {ipaddr}/{cidr}\n{essid}";
      #       on-click = "nm-connection-editor";
      #     };

      #     "pulseaudio" = {
      #       format = "{icon} {volume}%";
      #       format-muted = "";
      #       format-bluetooth = "{icon} {volume}%";
      #       format-bluetooth-muted = " ";
      #       format-icons = {
      #         default = [
      #           ""
      #           ""
      #           ""
      #         ];
      #       };
      #       on-click = "pavucontrol";
      #       on-click-right = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
      #     };

      #     "tray" = {
      #       icon-size = 16;
      #       spacing = 8;
      #     };
      # };
    };

    style = ''
      * {
        font-family: "${config.stylix.fonts.monospace.name}", "Font Awesome 6 Free", monospace;
        font-size: 13px;
        border-radius: 0px;
        border: none;
        min-height: 0;
      }

      window#waybar {
        background-color: @base00;
        opacity: 0.93;
        border-bottom: 2px solid #${colors.base0D};
      }

      #workspaces button {
        padding: 0 8px;
        background-color: transparent;
        color: #${colors.base05};
        border-bottom: 3px solid transparent;
        min-width: 36px;
      }

      #workspaces button:hover {
        background: #${colors.base02};
        box-shadow: inherit;
        border-bottom: 3px solid #${colors.base04};
      }

      #workspaces button.active {
        background-color: #${colors.base02};
        border-bottom: 3px solid #${colors.base0D};
        color: #${colors.base0D};
      }

      #workspaces button.urgent {
        background-color: #${colors.base08};
        color: #${colors.base00};
        animation: blink 0.5s linear infinite alternate;
      }

      #clock,
      #battery,
      #cpu,
      #memory,
      #temperature,
      #network,
      #pulseaudio,
      #tray,
      #window {
        padding: 0 10px;
        color: #${colors.base05};
      }

      #window {
        color: #${colors.base04};
        font-weight: 600;
      }

      #battery.charging {
        color: #${colors.base0B};
      }

      #battery.warning:not(.charging) {
        color: #${colors.base0A};
        animation: blink 2s linear infinite;
      }

      #battery.critical:not(.charging) {
        color: #${colors.base08};
        animation: blink 0.5s linear infinite;
      }

      #cpu.warning {
        color: #${colors.base0A};
      }

      #cpu.critical {
        color: #${colors.base08};
      }

      #memory.warning {
        color: #${colors.base0A};
      }

      #memory.critical {
        color: #${colors.base08};
      }

      #temperature.critical {
        color: #${colors.base08};
        animation: blink 0.5s linear infinite;
      }

      #network.disconnected {
        color: #${colors.base08};
      }

      #pulseaudio.muted {
        color: #${colors.base04};
      }

      @keyframes blink {
        to {
          color: #${colors.base00};
          background-color: #${colors.base08};
        }
      }

      tooltip {
        background: rgba(9, 11, 14, 0.93);
        border: 2px solid #4d9fff;
        border-radius: 0px;
      }

      tooltip label {
        color: #${colors.base05};
      }
    '';
  };

  # Better notification styling
  services.mako = {
    enable = true;

    settings = lib.mkForce {
      font = "${config.stylix.fonts.monospace.name} 11";
      background-color = "#${colors.base00}ee";
      text-color = "#${colors.base05}";
      border-color = "#${colors.base0D}";
      border-size = 2;
      border-radius = 0;
      padding = "10";
      margin = "20";
      default-timeout = 5000;
      layer = "overlay";
      width = 350;
      height = 200;
      progress-color = "over #${colors.base0D}";
      icons = true;
      max-icon-size = 64;
      markup = true;
      actions = true;
      history = true;
      max-history = 20;

      # Positioning on primary monitor
      anchor = "top-right";
    };

    extraConfig = ''
      [urgency=low]
      border-color=#${colors.base0B}
      default-timeout=3000

      [urgency=normal]
      border-color=#${colors.base0D}

      [urgency=high]
      border-color=#${colors.base08}
      background-color=#${colors.base00}ee
      text-color=#${colors.base08}
      default-timeout=0

      [category=volume]
      default-timeout=1000
      group-by=category
    '';
  };

  # Enhanced wofi config - fixed clipping issue
  programs.wofi = {
    enable = true;
    settings = lib.mkForce {
      width = 600;
      height = 450; # Reduced height to prevent clipping
      location = "center";
      show = "drun";
      prompt = "";
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
      matching = "fuzzy";
      sort_order = "alphabetical";
      hide_scroll = false; # Show scrollbar to prevent clipping
    };

    style = ''
      window {
        margin: 0px;
        background-color: rgba(${lib.removePrefix "#" colors.base00}, 0.95);
        border: 2px solid #${colors.base0D};
        border-radius: 0px;
      }

      #input {
        margin: 10px;
        padding: 10px;
        border: 2px solid #${colors.base02};
        border-radius: 0px;
        color: #${colors.base05};
        background-color: rgba(${lib.removePrefix "#" colors.base01}, 0.8);
        font-size: 14px;
      }

      #input:focus {
        border-color: #${colors.base0D};
      }

      #inner-box {
        margin: 10px;
        margin-bottom: 10px;  /* Ensure bottom margin */
        background-color: transparent;
        border-radius: 0px;
      }

      #outer-box {
        margin: 0px;
        padding: 0px;
        background-color: transparent;
        border-radius: 0px;
      }

      #scroll {
        margin: 0px;
        margin-bottom: 10px;  /* Add bottom margin to scroll container */
        background-color: transparent;
      }

      #text {
        margin: 2px;
        padding: 6px;
        color: #${colors.base05};
      }

      #entry {
        padding: 8px;
        margin: 4px;
        background-color: rgba(${lib.removePrefix "#" colors.base01}, 0.5);
        border: 2px solid transparent;
      }

      #entry:selected {
        background-color: rgba(${lib.removePrefix "#" colors.base02}, 0.8);
        border: 2px solid #${colors.base0D};
      }

      #text:selected {
        color: #${colors.base0D};
        font-weight: bold;
      }
    '';
  };

  # Add better lock screen
  programs.swaylock = {
    enable = true;
    settings = lib.mkForce {
      color = colors.base00;
      bs-hl-color = colors.base08;
      key-hl-color = colors.base0B;
      caps-lock-bs-hl-color = colors.base08;
      caps-lock-key-hl-color = colors.base0B;
      ring-color = colors.base02;
      ring-clear-color = colors.base0A;
      ring-ver-color = colors.base0D;
      ring-wrong-color = colors.base08;
      inside-color = "00000000";
      inside-clear-color = "00000000";
      inside-ver-color = "00000000";
      inside-wrong-color = "00000000";
      line-color = "00000000";
      line-clear-color = "00000000";
      line-ver-color = "00000000";
      line-wrong-color = "00000000";
      separator-color = "00000000";
      text-color = colors.base05;
      text-clear-color = colors.base05;
      text-ver-color = colors.base05;
      text-wrong-color = colors.base05;
      indicator-radius = 100;
      indicator-thickness = 10;
      font = config.stylix.fonts.monospace.name;
      font-size = 24;
      show-failed-attempts = true;
    };
  };

  home.packages = with pkgs; [
    # Core utilities
    brightnessctl
    grim
    grimblast
    hyprpaper
    hyprpicker
    jq
    libnotify
    pamixer
    pavucontrol
    playerctl
    slurp
    swappy
    swaybg
    # swaylock-effects
    # waybar-hyprland removed as it doesn't exist
    waybar # Standard waybar should work fine
    wev
    wl-clipboard
    wlr-randr
    wofi

    # Enhanced utilities
    cliphist
    eww
    font-awesome
    networkmanagerapplet
    swayidle
    wdisplays
    wlsunset

    # Screenshot/recording
    wf-recorder

    # System tray apps
    blueman
    tailscale-systray
  ];

  # Add hyprpaper config
  xdg.configFile."hypr/hyprpaper.conf".text = ''
    preload = ~/.config/wallpaper.png
    wallpaper = ,~/.config/wallpaper.png
    splash = false
  '';
}
