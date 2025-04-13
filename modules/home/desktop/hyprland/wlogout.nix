{
  config,
  lib,
  cfg,
  ...
}:

let
  inherit (config.lib.stylix) colors;
in
{
  enable = cfg.powerMenu == "wlogout";

  # Basic configuration
  layout = [
    {
      label = "lock";
      action =
        if cfg.lockScreen == "swaylock" then
          "swaylock"
        else if cfg.lockScreen == "swaylock-effects" then
          "swaylock --screenshots --clock --effect-blur 7x5"
        else if cfg.lockScreen == "hyprlock" then
          "hyprlock"
        else
          "swaylock";
      text = "Lock";
      keybind = "l";
    }
    {
      label = "logout";
      action = "hyprctl dispatch exit";
      text = "Logout";
      keybind = "e";
    }
    {
      label = "suspend";
      action = "systemctl suspend";
      text = "Suspend";
      keybind = "u";
    }
    {
      label = "shutdown";
      action = "systemctl poweroff";
      text = "Shutdown";
      keybind = "s";
    }
    {
      label = "reboot";
      action = "systemctl reboot";
      text = "Reboot";
      keybind = "r";
    }
    {
      label = "hibernate";
      action = "systemctl hibernate";
      text = "Hibernate";
      keybind = "h";
    }
  ];

  # Styling
  style = ''
    * {
      background-image: none;
      font-family: ${config.stylix.fonts.sansSerif.name};
      font-size: ${toString config.stylix.fonts.sizes.applications}px;
    }

    window {
      background-color: rgba(${lib.removePrefix "#" colors.base00}EE);
    }

    button {
      color: #${colors.base05};
      background-color: #${colors.base01};
      border-style: solid;
      border-width: 2px;
      border-radius: 10px;
      border-color: #${colors.base02};
      margin: 10px;
      background-repeat: no-repeat;
      background-position: center;
      background-size: 30%;
    }

    button:focus, button:active, button:hover {
      background-color: #${colors.base02};
      outline-style: none;
      border-color: #${colors.base0D};
    }

    #lock {
      background-image: image(url("$HOME/.config/wlogout/icons/lock.png"));
    }

    #logout {
      background-image: image(url("$HOME/.config/wlogout/icons/logout.png"));
    }

    #suspend {
      background-image: image(url("$HOME/.config/wlogout/icons/suspend.png"));
    }

    #hibernate {
      background-image: image(url("$HOME/.config/wlogout/icons/hibernate.png"));
    }

    #shutdown {
      background-image: image(url("$HOME/.config/wlogout/icons/shutdown.png"));
    }

    #reboot {
      background-image: image(url("$HOME/.config/wlogout/icons/reboot.png"));
    }
  '';
}
