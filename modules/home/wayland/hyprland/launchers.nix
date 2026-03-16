# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // launchers
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Application launchers: wofi and rofi configuration
#
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
  cfg = config.hyper-modern-nixos.launchers;
  colors = config.lib.stylix.colors;
in
{
  options.hyper-modern-nixos.launchers = {
    enable = mkEnableOption "Application launchers (wofi/rofi)";

    default = mkOption {
      type = types.enum [
        "wofi"
        "rofi"
      ];
      default = "wofi";
      description = "Default launcher";
    };

    wofi = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable wofi";
      };

      width = mkOption {
        type = types.int;
        default = 600;
        description = "Launcher width";
      };

      height = mkOption {
        type = types.int;
        default = 450;
        description = "Launcher height";
      };
    };

    rofi = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable rofi";
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; lib.optional cfg.wofi.enable wofi ++ lib.optional cfg.rofi.enable rofi;

    # ── Wofi ──────────────────────────────────────────────────────────────────
    programs.wofi = mkIf cfg.wofi.enable {
      enable = true;

      settings = lib.mkForce {
        width = cfg.wofi.width;
        height = cfg.wofi.height;
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
        hide_scroll = false;
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

        #input:focus { border-color: #${colors.base0D}; }

        #inner-box {
          margin: 10px;
          background-color: transparent;
        }

        #outer-box {
          margin: 0px;
          padding: 0px;
          background-color: transparent;
        }

        #scroll {
          margin: 0px;
          margin-bottom: 10px;
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

    # ── Rofi ──────────────────────────────────────────────────────────────────
    xdg.configFile."rofi/config.rasi" = mkIf cfg.rofi.enable {
      text = ''
        configuration {
          modi: "window,drun,run,ssh,filebrowser";
          show-icons: true;
          icon-theme: "Papirus";
          font: "${config.stylix.fonts.monospace.name} 12";
          terminal: "ghostty";
          window-format: "{w}  {c}  {t}";
          matching: "fuzzy";
          sort: true;
          case-sensitive: false;
        }

        @theme "theme"
      '';
    };

    xdg.configFile."rofi/theme.rasi" = mkIf cfg.rofi.enable {
      text = ''
        * {
          bg: #${colors.base00}ee;
          fg: #${colors.base05};
          selected: #${colors.base02};
          active: #${colors.base0D};
          urgent: #${colors.base08};

          background-color: @bg;
          text-color: @fg;
          border-color: @active;
        }

        window {
          width: 600px;
          border: 2px;
        }

        element selected {
          background-color: @selected;
          text-color: @active;
        }
      '';
    };
  };
}
