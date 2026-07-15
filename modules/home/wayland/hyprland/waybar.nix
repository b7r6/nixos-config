# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                               // hyper-modern-nixos // waybar
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    ;
  cfg = config.hyper-modern-nixos.waybar;
  colors = config.lib.stylix.colors;
in
{
  options.hyper-modern-nixos.waybar = {
    enable = mkEnableOption "Waybar status bar";

    position = mkOption {
      type = types.enum [
        "top"
        "bottom"
      ];
      default = "top";
      description = "Bar position";
    };

    height = mkOption {
      type = types.int;
      default = 30;
      description = "Bar height in pixels";
    };

    modules = {
      left = mkOption {
        type = types.listOf types.str;
        default = [
          "hyprland/workspaces"
          "hyprland/mode"
        ];
        description = "Left-side modules";
      };

      center = mkOption {
        type = types.listOf types.str;
        default = [ "hyprland/window" ];
        description = "Center modules";
      };

      right = mkOption {
        type = types.listOf types.str;
        default = [
          "pulseaudio"
          "network"
          "cpu"
          "memory"
          "clock"
          "tray"
        ];
        description = "Right-side modules";
      };
    };

    # ── Bar font (backported from new-suzuki) ────────────────────────────────
    font = {
      family = mkOption {
        type = types.str;
        default = "Orbitron";
        description = "Display font for the bar; falls back to the stylix monospace";
      };

      size = mkOption {
        type = types.int;
        default = 13;
        description = "Bar font size in px";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.waybar
      # bar display fonts + icon glyph coverage — every candidate face
      # installs, so font.family switches by string alone (cheap A/B via
      # waybar restart). chakra petch is the rayfish.xyz heading face
      # (squared techno, OFL); orbitron rounder sci-fi; azonix caps-only.
      pkgs.orbitron
      (pkgs.callPackage ./fonts/azonix.nix { })
      (pkgs.google-fonts.override { fonts = [ "Chakra Petch" ]; })
      pkgs.nerd-fonts.symbols-only
    ];

    programs.waybar = {
      enable = true;
      systemd.enable = true;

      settings.mainBar = {
        inherit (cfg) position;
        inherit (cfg) height;
        spacing = 4;

        modules-left = cfg.modules.left;
        modules-center = cfg.modules.center;
        modules-right = cfg.modules.right;

        "hyprland/workspaces" = { };
        "hyprland/mode" = {
          format = "<span style=\"italic\">{}</span>";
        };
        "hyprland/window" = { };

        tray.spacing = 10;

        clock = {
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          format-alt = "{:%Y-%m-%d}";
        };

        cpu = {
          format = "{usage}% ";
          tooltip = false;
        };

        memory.format = "{}% ";

        temperature = {
          critical-threshold = 80;
          format = "{temperatureC}°C {icon}";
          format-icons = [
            ""
            ""
            ""
          ];
        };

        network = {
          format-wifi = "{essid} ({signalStrength}%) ";
          format-ethernet = "{ipaddr}/{cidr} ";
          tooltip-format = "{ifname} via {gwaddr} ";
          format-disconnected = "Disconnected ⚠";
        };

        pulseaudio = {
          format = "{volume}% {icon}";
          format-muted = " ";
          format-icons.default = [
            ""
            ""
            ""
          ];
          on-click = "pavucontrol";
        };

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{capacity}% {icon}";
          format-charging = "{capacity}% ";
          format-plugged = "{capacity}% ";
          format-icons = [
            ""
            ""
            ""
            ""
            ""
          ];
        };

        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "";
            deactivated = "";
          };
        };
      };

      style = ''
        * {
          font-family: "${cfg.font.family}", "${config.stylix.fonts.monospace.name}", "Symbols Nerd Font", monospace;
          font-size: ${toString cfg.font.size}px;
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
        }

        #clock, #battery, #cpu, #memory, #temperature, #network, #pulseaudio, #tray, #window {
          padding: 0 10px;
          color: #${colors.base05};
        }

        #window {
          color: #${colors.base04};
          font-weight: 600;
        }

        #battery.charging { color: #${colors.base0B}; }
        #battery.warning:not(.charging) { color: #${colors.base0A}; }
        #battery.critical:not(.charging) { color: #${colors.base08}; }
        #network.disconnected { color: #${colors.base08}; }
        #pulseaudio.muted { color: #${colors.base04}; }

        tooltip {
          background: rgba(9, 11, 14, 0.93);
          border: 2px solid #${colors.base0D};
        }

        tooltip label { color: #${colors.base05}; }
      '';
    };
  };
}
