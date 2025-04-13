{
  config,
  lib,
  cfg,
  pkgs,
  ...
}:

let
  inherit (config.lib.stylix) colors;
in
{
  enable = cfg.lockScreen == "swaylock" || cfg.lockScreen == "swaylock-effects";
  package = if cfg.lockScreen == "swaylock-effects" then pkgs.swaylock-effects else pkgs.swaylock;
  settings = {
    # Appearance
    color = lib.removePrefix "#" colors.base00;
    font = config.stylix.fonts.sansSerif.name;
    font-size = config.stylix.fonts.sizes.applications;
    indicator-idle-visible = true;
    indicator-radius = 100;
    indicator-thickness = 7;
    show-failed-attempts = true;

    # Effects (only used when swaylock-effects is enabled)
    effect-blur = lib.mkIf (cfg.lockScreen == "swaylock-effects") "7x5";
    effect-vignette = lib.mkIf (cfg.lockScreen == "swaylock-effects") "0.5:0.5";

    # Colors
    bs-hl-color = lib.removePrefix "#" colors.base08;
    key-hl-color = lib.removePrefix "#" colors.base0D;
    separator-color = lib.removePrefix "#" colors.base01;
    text-color = lib.removePrefix "#" colors.base05;
    text-clear-color = lib.removePrefix "#" colors.base05;
    text-caps-lock-color = lib.removePrefix "#" colors.base09;
    text-ver-color = lib.removePrefix "#" colors.base05;
    text-wrong-color = lib.removePrefix "#" colors.base05;
    inside-color = lib.removePrefix "#" colors.base00;
    inside-clear-color = lib.removePrefix "#" colors.base0C;
    inside-caps-lock-color = lib.removePrefix "#" colors.base09;
    inside-ver-color = lib.removePrefix "#" colors.base0D;
    inside-wrong-color = lib.removePrefix "#" colors.base08;
    line-color = "00000000";
    line-clear-color = "00000000";
    line-caps-lock-color = "00000000";
    line-ver-color = "00000000";
    line-wrong-color = "00000000";
    ring-color = lib.removePrefix "#" colors.base02;
    ring-clear-color = lib.removePrefix "#" colors.base0C;
    ring-caps-lock-color = lib.removePrefix "#" colors.base09;
    ring-ver-color = lib.removePrefix "#" colors.base0D;
    ring-wrong-color = lib.removePrefix "#" colors.base08;
  };
}
