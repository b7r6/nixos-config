# HyprPanel configuration with Ono-Sendai theme support
{ config, lib, pkgs, flake, ... }:

let
  inherit (flake) inputs;
  
  # Get the theme colors
  onoSendaiColors = config.themes.colors;
in
{
  options.services.hyprpanel = {
    enable = lib.mkEnableOption "Enable HyprPanel with Ono-Sendai theme";
  };

  config = lib.mkIf config.services.hyprpanel.enable {
    # Add overlay for HyprPanel
    nixpkgs.overlays = [
      (final: prev: {
        hyprpanel = inputs.hyprpanel.packages.${pkgs.system}.default;
      })
    ];
    
    # Add HyprPanel package
    home.packages = [ pkgs.hyprpanel ];
    
    # Configure HyprPanel
    programs.hyprpanel = {
      enable = true;
      overlay.enable = true;
      hyprland.enable = true;
      systemd.enable = true;
      config.enable = true;
      
      # Create custom theme based on Ono-Sendai colors
      settings = {
        # Custom theme settings
        theme = {
          name = "";
          font = {
            name = "Berkeley Mono SemiBold";
            size = "1.2rem";
            weight = 600;
          };
          
          bar = {
            opacity = 100;
            transparent = false;
            border = {
              location = "bottom";
              width = "0.15em";
            };
            border_radius = "0.4em";
            dropdownGap = "2.9em";
            enableShadow = true;
            shadow = "0px 2px 3px 2px ${onoSendaiColors.backgroundDark}";
            shadowMargins = "5px 5px";
            buttons = {
              style = "default";
              radius = "0.3em";
              enableBorders = true;
              borderSize = "0.12em";
              opacity = 100;
              
              # Adjust button colors
              background = onoSendaiColors.background;
              background_hover = onoSendaiColors.backgroundLight;
              border = onoSendaiColors.border;
              border_hover = onoSendaiColors.accentPrimary;
              foreground = onoSendaiColors.foreground;
              foreground_hover = onoSendaiColors.textPrimary;
            };
            
            # Set colors for menus
            menus = {
              background = onoSendaiColors.background;
              border = {
                color = onoSendaiColors.border;
                size = "0.13em";
                radius = "0.7em";
              };
              text = onoSendaiColors.textPrimary;
              buttons = {
                background = onoSendaiColors.backgroundLight;
                background_hover = onoSendaiColors.border;
                border = onoSendaiColors.border;
                border_hover = onoSendaiColors.accentPrimary;
                text = onoSendaiColors.textPrimary;
                text_hover = onoSendaiColors.brightWhite;
              };
            };
          };
          
          # OSD settings
          osd = {
            background = onoSendaiColors.background;
            border = {
              color = onoSendaiColors.border;
              size = "0.1em";
            };
            text = onoSendaiColors.textPrimary;
            bar = {
              background = onoSendaiColors.backgroundLight;
              foreground = onoSendaiColors.accentPrimary;
              border = onoSendaiColors.border;
            };
          };
          
          # Notification settings
          notification = {
            background = onoSendaiColors.background;
            border = {
              color = onoSendaiColors.border;
              radius = "0.6em";
            };
            title = onoSendaiColors.accentPrimary;
            text = onoSendaiColors.textPrimary;
            button = {
              background = onoSendaiColors.backgroundLight;
              background_hover = onoSendaiColors.border;
              foreground = onoSendaiColors.textPrimary;
              foreground_hover = onoSendaiColors.brightWhite;
            };
          };
        };
        
        # Panel layout - can be customized as needed
        layout = {
          "bar.layouts" = {
            "0" = {
              left = [ "workspaces" "windowtitle" ];
              center = [ "media" ];
              right = [ "microphone" "volume" "network" "bluetooth" "battery" "systray" "clock" "notifications" ];
            };
          };
        };
        
        # Module settings
        bar = {
          # Battery module configuration
          battery = {
            label = true;
            hideLabelWhenFull = false;
            rightClick = "menu:energy";
          };
          
          # Volume module
          volume = {
            label = true;
            rightClick = "menu:audio";
          };
          
          # Workspaces configuration
          workspaces = {
            show_icons = true;
            showApplicationIcons = true;
            applicationIconOncePerWorkspace = true;
            showWsIcons = true;
            show_numbered = false;
            workspaces = 10;
            spacing = 0.8;
            monitorSpecific = true;
            
            # Icons
            icons = {
              active = "";
              occupied = "";
              available = "";
            };
            
            applicationIconMap = {
              "class:kitty" = "";
              "class:org.wezfurlong.wezterm" = "";
              "class:firefox" = "";
              "class:Emacs" = "";
            };
          };
          
          # Window title
          windowtitle = {
            label = true;
            icon = true;
            class_name = true;
            truncation = true;
            truncation_size = 50;
          };
          
          # Clock settings
          clock = {
            format = "%I:%M:%S %p";
            showIcon = true;
            rightClick = "menu:calendar";
          };
          
          # Network settings
          network = {
            label = true;
            showWifiInfo = true;
            rightClick = "menu:network";
          };
          
          # Bluetooth settings
          bluetooth = {
            label = true;
            rightClick = "menu:bluetooth";
          };
          
          # Media settings
          media = {
            truncation = true;
            truncation_size = 40;
            rightClick = "menu:media";
          };
        };
        
        # Menu configurations
        menus = {
          # Dashboard configuration
          dashboard = {
            # Power menu settings
            powermenu = {
              shutdown = "systemctl poweroff";
              reboot = "systemctl reboot";
              logout = "hyprctl dispatch exit";
              sleep = "systemctl suspend";
            };
          };
          
          # Calendar configuration
          clock = {
            time = {
              military = false;
              hideSeconds = false;
            };
          };
        };
        
        # Notification settings
        notifications = {
          monitor = 0;
          active_monitor = true;
          position = "top right";
          timeout = 5000;
        };
      };
    };
    
    # Make HyprPanel start with Hyprland
    wayland.windowManager.hyprland.settings.exec-once = [
      "hyprpanel"
    ];
  };
} 