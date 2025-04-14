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
in
{
  imports = [
    inputs.hyprland.homeManagerModules.default
    ./hyprpanel.nix
  ];

  wayland.windowManager.hyprland = {
    enable = cfg.enable;
    systemd.enable = true;

    plugins = [
      inputs.hy3.outputs.packages.${pkgs.system}.hy3
    ];

    settings =
      let
        inherit (config.lib.stylix) colors;

        # Extract color values without # prefix for Hyprland
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
        # Monitor configuration
        monitor = [
          "DP-5,3440x1440@100,0x0,1"
          "eDP-1,3840x2400@100@100,0x0,2.5"
        ];

        # General settings
        general = {
          gaps_in = 5;
          gaps_out = 10;
          border_size = 2;

          "col.active_border" = lib.mkForce "rgba(${base0D}ee) rgba(${base0E}ee) 45deg";
          "col.inactive_border" = lib.mkForce "rgba(${base02}aa)";

          layout = "dwindle";
        };

        # Decoration settings
        decoration = {
          blur = {
            enabled = true;
            size = 3;
            passes = 1;
          };
        };

        # Animation settings
        animations = {
          enabled = true;
          bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";

          animation = [
            "windows, 1, 7, myBezier"
            "windowsOut, 1, 7, default, popin 80%"
            "border, 1, 10, default"
            "fade, 1, 7, default"
            "workspaces, 1, 6, default"
          ];
        };

        # Input settings
        input = {
          kb_layout = "us";
          follow_mouse = 1;
          sensitivity = 0.0; # -1.0 - 1.0, 0 means no modification

          touchpad = {
            natural_scroll = true;
          };

          kb_options = "ctrl:nocaps";
        };

        # Layout settings
        dwindle = {
          pseudotile = true;
          preserve_split = true;
        };

        # Misc settings
        misc = {
          force_default_wallpaper = 0;
        };

        # hy3
        plugin.hy3 = {
          tabs = {
            border_width = 1;
            "col.active_border" = lib.mkForce "rgba(${base0D}ee) rgba(${base0E}ee) 45deg";
            "col.inactive_border" = lib.mkForce "rgba(${base02}aa)";
          };

          autotile = {
            enable = true;
            trigger_width = 800;
            trigger_height = 500;
          };
        };

        # Key bindings
        "$mod" = "SUPER";
        bind = [
          # Core bindings
          "$mod, Return, exec, wezterm"
          "$mod, Space, exec, wofi --show drun"
          "$mod, Q, killactive"
          "$mod SHIFT, Q, exit"
          "$mod, E, exec, dolphin"

          # Window management
          "$mod, F, fullscreen, 1"
          "$mod SHIFT, F, fullscreen, 0"
          "$mod, V, togglefloating"
          "$mod, T, pseudo"
          "$mod, S, togglesplit"

          # Focus navigation (vim-style)
          "$mod, H, movefocus, l"
          "$mod, L, movefocus, r"
          "$mod, K, movefocus, u"
          "$mod, J, movefocus, d"

          # Move windows (vim-style)
          "$mod SHIFT, H, movewindow, l"
          "$mod SHIFT, L, movewindow, r"
          "$mod SHIFT, K, movewindow, u"
          "$mod SHIFT, J, movewindow, d"

          # Resize windows (vim-style with Alt)
          "$mod ALT, H, resizeactive, -20 0"
          "$mod ALT, L, resizeactive, 20 0"
          "$mod ALT, K, resizeactive, 0 -20"
          "$mod ALT, J, resizeactive, 0 20"

          # Workspace switching
          "$mod, 1, workspace, 1"
          "$mod, 2, workspace, 2"
          "$mod, 3, workspace, 3"
          "$mod, 4, workspace, 4"
          "$mod, 5, workspace, 5"
          "$mod, 6, workspace, 6"
          "$mod, 7, workspace, 7"
          "$mod, 8, workspace, 8"
          
          # Move active window to workspace
          "$mod SHIFT, 1, movetoworkspace, 1"
          "$mod SHIFT, 2, movetoworkspace, 2"
          "$mod SHIFT, 3, movetoworkspace, 3"
          "$mod SHIFT, 4, movetoworkspace, 4"
          "$mod SHIFT, 5, movetoworkspace, 5"
          "$mod SHIFT, 6, movetoworkspace, 6"
          "$mod SHIFT, 7, movetoworkspace, 7"
          "$mod SHIFT, 8, movetoworkspace, 8"

          # Cycle through workspaces
          "$mod, Tab, exec, hyprctl dispatch cyclenext"
          "$mod SHIFT, Tab, exec, hyprctl dispatch cyclenext prev"
        ];

        # Mouse bindings
        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];

        # Startup applications
        exec-once = [
          "blueman-applet"
          "hyprpaper"
          "tailscale-systray"
          "waybar"
        ];
      };
  };

  programs.waybar =
    let
      inherit (config.lib.stylix) colors;
    in
    {
      enable = true;

      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 32;
          spacing = 4;

          modules-left = [
            "hyprland/workspaces"
            "hyprland/window"
          ];

          modules-center = [ "clock" ];

          modules-right = [
            "battery"
            "cpu"
            "memory"
            "network"
            "pulseaudio"
            "temperature"
            "tray"
          ];

          "hyprland/workspaces" = {
            format = "{name}"; # Show both number and label from virtual-desktops

            persistent-workspaces = {
              "1" = [ ]; # Always show workspace 1
              "2" = [ ]; # Always show workspace 2
              "3" = [ ]; # Always show workspace 3
              "4" = [ ]; # Always show workspace 4
              "5" = [ ]; # Always show workspace 5
              "6" = [ ]; # Always show workspace 6
              "7" = [ ]; # Always show workspace 7
              "8" = [ ]; # Always show workspace 8
            };

            sort-by-number = true;
          };

          "clock" = {
            format = "⌚ {:%H:%M}";
            format-alt = "⌚ {:%Y-%m-%d}";
            tooltip-format = "⌚ {:%Y-%m-%d} | ⌚ {:%H:%M}";
          };

          "cpu" = {
            format = "⚙ {usage}%";
            tooltip = false;
          };

          "memory" = {
            format = "⬗ {used:0.1f}GB";
          };

          "temperature" = {
            critical-threshold = 80;
            format = "🌡 {temperatureC}°C {icon}";

            format-icons = [
              "✓"
              "⚠"
              "⚠"
            ];
          };

          "battery" = {
            states = {
              good = 95;
              warning = 30;
              critical = 15;
            };

            format = "{capacity}% {icon}";
            format-charging = "{capacity}% ⚡";
            format-plugged = "{capacity}% ⚡";
            format-alt = "{time} {icon}";

            format-icons = [
              "□"
              "▣"
              "▣"
              "▣"
              "■"
            ];
          };

          "network" = {
            format-wifi = "→ {essid} ({signalStrength}%)";
            format-ethernet = "⌁ {ipaddr}/{cidr}";
            tooltip-format = "⌁ {ifname} via {gwaddr}";
            format-linked = "⌁ {ifname} (No IP)";
            format-disconnected = "✗ Disconnected";
            format-alt = "⌁ {ifname}: {ipaddr}/{cidr}";

            on-click = "nm-applet";
          };

          "pulseaudio" = {
            format = "♪ {volume}% {icon} {format_source}";
            format-bluetooth = "♫ {volume}% {icon} {format_source}";
            format-bluetooth-muted = "♫× {icon} {format_source}";
            format-muted = "♪× {format_source}";
            format-source = "▲ {volume}%";
            format-source-muted = "▼ ×";

            format-icons = {
              headphone = "♫";
              hands-free = "☊";
              headset = "☊";
              phone = "☎";
              portable = "☎";
              car = "⚙";
              default = [
                "♪"
                "♪"
                "♫"
              ];
            };

            on-click = "pavucontrol";
          };

          "tray" = {
            icon-size = 21;
            spacing = 10;
          };
        };
      };

      style = ''
        * {
          font-family: "${config.stylix.fonts.monospace.name}", "Font Awesome 6 Free";
          font-size: ${toString config.stylix.fonts.sizes.applications}px;
          border-radius: 0px;
        }

        window#waybar {
          background-color: #${colors.base00};
          color: #${colors.base05};
          transition-property: background-color;
          transition-duration: .5s;
        }

        window#waybar.hidden {
          opacity: 0.2;
        }

        /* Enhanced workspace styling */
        #workspaces button {
          padding: 0 8px;
          background-color: transparent;
          color: #${colors.base05};
          border-bottom: 3px solid #${colors.base05};
          font-weight: bold;
        }

        #workspaces button .name {
          font-size: ${toString (config.stylix.fonts.sizes.applications - 1)}px;
          padding-left: 5px;
          color: #${colors.base04};
        }

        #workspaces button:hover {
          background: #${colors.base02};
        }

        #workspaces button.active {
          background-color: #${colors.base02};
        }

        #workspaces button.active .name {
          color: #${colors.base0D};
        }

        #workspaces button.urgent {
          background-color: #${colors.base08};
        }

        #mode {
          background-color: #${colors.base02};
          border-bottom: 3px solid #${colors.base05};
        }

        #clock,
        #battery,
        #cpu,
        #memory,
        #disk,
        #temperature,
        #network,
        #pulseaudio,
        #custom-media,
        #tray,
        #mode,
        #idle_inhibitor,
        #mpd {
          padding: 0 10px;
          margin: 0 4px;
          color: #${colors.base05};
        }

        #window,
        #workspaces {
          margin: 0 4px;
        }

        #battery.charging, #battery.plugged {
          color: #${colors.base0B};
        }

        #battery.critical:not(.charging) {
          background-color: #${colors.base08};
          color: #${colors.base05};
          animation-name: blink;
          animation-duration: 0.5s;
          animation-timing-function: linear;
          animation-iteration-count: infinite;
          animation-direction: alternate;
        }

        #temperature.critical {
          background-color: #${colors.base08};
        }

        @keyframes blink {
          to {
            background-color: #${colors.base05};
            color: #${colors.base00};
          }
        }
      '';
    };

  # Notification daemon (mako)
  # Uses the Stylix colors automatically through the stylix.targets
  services.mako.enable = true;

  home.packages = with pkgs; [
    blueman
    grim
    hyprpaper
    mako
    nm-tray
    pavucontrol
    playerctl
    slurp
    swappy
    tailscale-systray
    waybar
    wl-clipboard
    wl-color-picker
    wl-gammactl
    wl-kbptr
    wlsunset
    wofi
  ];

  home.file.".config/wofi/style.css".text =
    let
      inherit (config.lib.stylix) colors;
    in
    ''
      window {
        margin: 0px;
        background-color: ${colors.base00};
        border-radius: 0px;
        border: 2px solid ${colors.base0D};
      }

      #input {
        margin: 5px;
        border: 2px solid ${colors.base02};
        border-radius: 0px;
        color: ${colors.base05};
        background-color: ${colors.base01};
      }

      #inner-box {
        margin: 5px;
        background-color: ${colors.base00};
        border-radius: 0px;
      }

      #outer-box {
        margin: 5px;
        padding: 10px;
        background-color: ${colors.base00};
        border-radius: 0px;
      }

      #scroll {
        margin: 5px;
        background-color: ${colors.base00};
        border-radius: px;
      }

      #text {
        margin: 5px;
        color: ${colors.base05};
      }

      #entry:selected {
        background-color: ${colors.base02};
        border-radius: 5px;
      }

      #text:selected {
        color: ${colors.base0D};
      }
    '';

  # Create a directory for default wallpaper just in case
  home.file.".config/hypr/.keep".text = "";
}
