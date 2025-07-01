{ config, ... }:

let
  inherit (config.lib.stylix) colors;
in
{
  enable = true;
  # Use systemd to manage Waybar
  systemd.enable = true;

  # Style files
  style = ''
    * {
      font-family: "${config.stylix.fonts.monospace.name}", "Font Awesome 6 Free", "Material Design Icons";
      font-size: ${toString config.stylix.fonts.sizes.applications}px;
      border-radius: 8px;
    }

    window#waybar {
      background: alpha(#${colors.base00}, 0.9);
      color: #${colors.base05};
      border-bottom: 3px solid alpha(#${colors.base0D}, 0.8);
      transition-property: background-color;
      transition-duration: .5s;
    }

    window#waybar.hidden {
      opacity: 0.2;
    }

    #workspaces {
      background: alpha(#${colors.base01}, 0.6);
      margin: 5px 5px;
      padding: 0 8px;
      border-radius: 10px;
    }

    #workspaces button {
      padding: 0 8px;
      background: transparent;
      color: #${colors.base05};
      border-radius: 10px;
      margin: 4px 0;
      transition: all 0.3s ease-in-out;
    }

    #workspaces button:hover {
      background: alpha(#${colors.base02}, 0.5);
      box-shadow: inherit;
      text-shadow: inherit;
    }

    #workspaces button.active {
      background: alpha(#${colors.base0D}, 0.8);
      color: #${colors.base00};
    }

    #workspaces button.urgent {
      background-color: #${colors.base08};
    }

    tooltip {
      background: #${colors.base00};
      border: 2px solid #${colors.base0D};
    }

    tooltip label {
      color: #${colors.base05};
    }

    #mode {
      background: #${colors.base0A};
      color: #${colors.base00};
      padding: 0 10px;
      margin: 5px;
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
    #custom-power,
    #idle_inhibitor,
    #mpd,
    #bluetooth,
    #custom-notification {
      background: alpha(#${colors.base01}, 0.6);
      padding: 0 12px;
      margin: 5px 2px;
      border-radius: 10px;
      color: #${colors.base05};
    }

    #window {
      color: #${colors.base05};
      background: alpha(#${colors.base01}, 0.6);
      margin: 5px;
      padding: 0 10px;
      border-radius: 10px;
    }

    /* Module-specific styling */

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

    #network.disconnected {
      background-color: alpha(#${colors.base08}, 0.5);
    }

    #temperature.critical {
      background-color: #${colors.base08};
    }

    #custom-power {
      background-color: alpha(#${colors.base08}, 0.7);
      color: #${colors.base00};
      font-size: ${toString (config.stylix.fonts.sizes.applications - 1)}px;
      margin-right: 5px;
    }

    #pulseaudio.muted {
      background-color: alpha(#${colors.base09}, 0.5);
    }

    @keyframes blink {
      to {
        background-color: #${colors.base05};
        color: #${colors.base00};
      }
    }
  '';

  # Settings configuration
  settings = {
    mainBar = {
      layer = "top";
      position = "top";
      height = 36;
      margin-top = 6;
      margin-left = 8;
      margin-right = 8;
      spacing = 0;

      # GTK module to inherit GTK theme colors
      modules-left = [
        "hyprland/workspaces"
        "hyprland/window"
      ];

      modules-center = [ "clock" ];

      modules-right = [
        "tray"
        "pulseaudio"
        "bluetooth"
        "network"
        "cpu"
        "memory"
        "temperature"
        "battery"
        "custom/notification"
        "custom/power"
      ];

      # Module configuration
      "hyprland/workspaces" = {
        format = "{icon}";
        on-click = "activate";
        all-outputs = true;
        format-icons = {
          "1" = "󰙯"; # Terminal
          "2" = "󰖟"; # Web
          "3" = "󰠮"; # Code
          "4" = "󰉋"; # Documents
          "5" = "󰇮"; # Music
          "6" = "󰍡"; # Communication
          "7" = "󰏆"; # Games
          "8" = "󰂺"; # Art
          "9" = "󰕧"; # Settings
          "10" = "󰍹"; # Extra
          "urgent" = "󰀨";
          "default" = "󰄯";
        };
      };

      "hyprland/window" = {
        max-length = 50;
      };

      "clock" = {
        format = "{:%I:%M %p}";
        format-alt = "{:%Y-%m-%d %A}";
        tooltip-format = "<tt>{calendar}</tt>";
        calendar = {
          mode = "month";
          on-scroll = 1;
          format = {
            months = "<span color='#${colors.base0D}'><b>{}</b></span>";
            weekdays = "<span color='#${colors.base0E}'><b>{}</b></span>";
            today = "<span color='#${colors.base08}'><b>{}</b></span>";
          };
        };
        actions = {
          on-click-right = "mode";
          on-scroll-up = "shift_up";
          on-scroll-down = "shift_down";
        };
      };

      "cpu" = {
        format = "{usage}% 󰻠";
        tooltip = true;
        interval = 2;
      };

      "memory" = {
        format = "{}% 󰍛";
        interval = 2;
      };

      "temperature" = {
        critical-threshold = 80;
        format = "{temperatureC}°C {icon}";
        format-icons = [
          "󰔏"
          "󰔐"
          "󱃂"
        ];
      };

      "battery" = {
        states = {
          good = 90;
          warning = 30;
          critical = 15;
        };
        format = "{capacity}% {icon}";
        format-charging = "{capacity}% 󰂄";
        format-plugged = "{capacity}% 󰚥";
        format-alt = "{time} {icon}";
        format-icons = [
          "󰂎"
          "󰁺"
          "󰁻"
          "󰁼"
          "󰁽"
          "󰁾"
          "󰁿"
          "󰂀"
          "󰂁"
          "󰂂"
          "󰁹"
        ];
        tooltip-format = "{timeTo} {power}W";
      };

      "network" = {
        format-wifi = "{essid} ({signalStrength}%) 󰖩";
        format-ethernet = "{ipaddr}/{cidr} 󰈀";
        tooltip-format = "{ifname} via {gwaddr} 󰈀";
        format-linked = "{ifname} (No IP) 󰌙";
        format-disconnected = "Disconnected 󰌙";
        format-alt = "{ifname}: {ipaddr}/{cidr}";
        on-click-right = "nm-connection-editor";
      };

      "bluetooth" = {
        format = " {status}";
        format-disabled = "󰂲";
        format-connected = "󰂱 {device_alias}";
        format-connected-battery = "󰂱 {device_alias} {device_battery_percentage}%";
        tooltip-format = "{controller_alias}\t{controller_address}";
        tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
        tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
        on-click = "blueman-manager";
      };

      "pulseaudio" = {
        format = "{volume}% {icon}";
        format-bluetooth = "{volume}% {icon}󰂰";
        format-bluetooth-muted = "󰖁 {icon}󰂲";
        format-muted = "󰖁";
        format-source = "{volume}% 󰍬";
        format-source-muted = "󰍭";
        format-icons = {
          headphone = "󰋋";
          hands-free = "󰋎";
          headset = "󰋎";
          phone = "󰏲";
          portable = "󰄝";
          car = "󰄋";
          default = [
            "󰕿"
            "󰖀"
            "󰕾"
          ];
        };
        on-click = "pavucontrol";
        on-click-right = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        tooltip-format = "{desc}, {volume}%";
      };

      "tray" = {
        icon-size = 18;
        spacing = 10;
      };

      "custom/notification" = {
        tooltip = false;
        format = "{icon}";
        format-icons = {
          notification = "<span foreground='#${colors.base0A}'>󱅫</span>";
          none = "󰂚";
          dnd-notification = "<span foreground='#${colors.base08}'>󰂛</span>";
          dnd-none = "<span foreground='#${colors.base08}'>󰂛</span>";
          inhibited-notification = "<span foreground='#${colors.base0A}'>󱅫</span>";
          inhibited-none = "󰂚";
          dnd-inhibited-notification = "<span foreground='#${colors.base08}'>󰂛</span>";
          dnd-inhibited-none = "<span foreground='#${colors.base08}'>󰂛</span>";
        };
        return-type = "json";
        exec-if = "which swaync-client";
        exec = "swaync-client -swb";
        on-click = "swaync-client -t -sw";
        on-click-right = "swaync-client -d -sw";
        escape = true;
      };

      "custom/power" = {
        format = "⏻";
        on-click = "wlogout";
        tooltip = false;
      };
    };
  };
}
