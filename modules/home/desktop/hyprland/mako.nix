{
  config,
  cfg,
  ...
}:

let
  inherit (config.lib.stylix) colors;
in
{
  enable = cfg.enableMako;

  # Appearance
  font = "${config.stylix.fonts.sansSerif.name} ${toString config.stylix.fonts.sizes.applications}pt";
  width = 400;
  height = 150;
  margin = "20";
  padding = "15";
  borderSize = 2;
  borderRadius = 10;
  defaultTimeout = 10000;
  layer = "overlay";

  # Colors
  backgroundColor = "${colors.base00}DD";
  textColor = "${colors.base05}";
  borderColor = "${colors.base0D}";
  progressColor = "over ${colors.base0E}";

  # Icons
  icons = true;
  maxIconSize = 48;

  # Extra styling
  markup = true;
  actions = true;

  # Different styling for different urgency levels
  extraConfig = ''
    [urgency=low]
    border-color=${colors.base0C}

    [urgency=normal]
    border-color=${colors.base0D}

    [urgency=high]
    border-color=${colors.base08}
    background-color=${colors.base00}EE

    [category=mpd]
    default-timeout=2000
    group-by=category

    [category=email]
    default-timeout=0

    [app-name=telegram-desktop]
    border-color=${colors.base0B}
  '';
}
