# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // lockscreen
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Lock screen (swaylock) configuration.
#
# TODO[b7r6]: figure out how this fuckin thing works...
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    ;
  cfg = config.hyper-modern-nixos.lockscreen;
  colors = config.lib.stylix.colors;
  # The EYES card behind the lock indicator — the kernel's own CPU render,
  # so the lock screen and the live wallpaper are the same scene. This pulls
  # straylight-nvidia-sdk (CUDA), so it's opt-in: only GB10 hosts that run
  # the field want it, and Nix's laziness keeps the dep off every other host
  # as long as `eyesStill` stays false (the thunk is never forced).
  eyesStill = import ../../themes/wallpapers/eyes-still.nix { inherit pkgs flake; };
in
{
  options.hyper-modern-nixos.lockscreen = {
    enable = mkEnableOption "Lock screen (swaylock)";

    eyesStill = mkEnableOption "kernel-rendered EYES still behind the lock (needs the CUDA SDK; GB10 only)";

    indicatorRadius = mkOption {
      type = types.int;
      default = 100;
      description = "Lock indicator radius";
    };

    showFailedAttempts = mkOption {
      type = types.bool;
      default = true;
      description = "Show failed login attempts";
    };
  };

  config = mkIf cfg.enable {
    programs.swaylock = {
      enable = true;

      settings = lib.mkForce (
        lib.optionalAttrs cfg.eyesStill {
          image = "${eyesStill}/eyes.png";
          scaling = "fill";
        }
        // {
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
          indicator-radius = cfg.indicatorRadius;
          indicator-thickness = 10;
          font = config.stylix.fonts.monospace.name;
          font-size = 24;
          show-failed-attempts = cfg.showFailedAttempts;
        }
      );
    };
  };
}
