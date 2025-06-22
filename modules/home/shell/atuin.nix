{
  config,
  lib,
  pkgs,
  ...
}:
let
  colors = config.hyper-modern-nixos.themes.palette;
in
{
  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;

    settings = {
      update_check = false;

      dialect = "us";
      style = "auto";

      theme = {
        # Base = colors.base05;
        # Title = colors.base0D;
        # Important = colors.base0E;
        # Annotation = colors.base03;
        # Guidance = colors.base0C;
        # AlertInfo = colors.base0B;
        # AlertWarn = colors.base0A;
        # AlertError = colors.base08;
      };
    };
  };
}
