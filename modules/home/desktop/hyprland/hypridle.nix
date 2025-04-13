{
  config,
  lib,
  cfg,
  pkgs,
  ...
}:

let
  # Get the appropriate lock command
  lockCmd =
    if cfg.lockScreen == "swaylock" then
      "${pkgs.swaylock}/bin/swaylock"
    else if cfg.lockScreen == "swaylock-effects" then
      "${pkgs.swaylock-effects}/bin/swaylock --screenshots --clock --effect-blur 7x5"
    else if cfg.lockScreen == "hyprlock" then
      "${pkgs.hyprlock}/bin/hyprlock"
    else
      "${pkgs.swaylock}/bin/swaylock";
in
{
  enable = cfg.idleManager == "hypridle";
  lockCmd = lockCmd;
  beforeSleepCmd = lockCmd;
  afterSleepCmd = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";

  timeouts = [
    {
      timeout = 300;
      command = lockCmd;
    }
    {
      timeout = 380;
      command = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off";
    }
  ];

  listeners = [
    {
      name = "reset-dpms";
      timeout = 0;
      onResume = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
    }
  ];
}
