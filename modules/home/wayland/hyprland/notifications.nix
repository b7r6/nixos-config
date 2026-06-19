# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                         // hyper-modern-nixos // notifications
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Notification daemon (mako) configuration
#
{ config, lib, ... }:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    ;
  cfg = config.hyper-modern-nixos.notifications;
  colors = config.lib.stylix.colors;
in
{
  options.hyper-modern-nixos.notifications = {
    enable = mkEnableOption "Notification daemon (mako)";

    position = mkOption {
      type = types.enum [
        "top-right"
        "top-left"
        "bottom-right"
        "bottom-left"
        "top-center"
        "bottom-center"
      ];
      default = "top-right";
      description = "Notification position";
    };

    timeout = mkOption {
      type = types.int;
      default = 5000;
      description = "Default notification timeout in ms";
    };

    maxVisible = mkOption {
      type = types.int;
      default = 5;
      description = "Maximum visible notifications";
    };

    width = mkOption {
      type = types.int;
      default = 350;
      description = "Notification width";
    };
  };

  config = mkIf cfg.enable {
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
        default-timeout = cfg.timeout;
        layer = "overlay";
        inherit (cfg) width;
        height = 200;
        max-visible = cfg.maxVisible;
        progress-color = "over #${colors.base0D}";
        icons = true;
        max-icon-size = 64;
        markup = true;
        actions = true;
        history = true;
        max-history = 20;
        anchor = cfg.position;
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
  };
}
