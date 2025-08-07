{ config, lib, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.themes;

  themes = {
    # TODO[b7r6]: in general we want to get in the habit of making `builtin.path`
    # calls (for a few reasons), decide on this later...
    ono-sendai-blue = import ../../../design/palettes/ono-sendai/blue.nix;
    ono-sendai-tactical = import ../../../design/palettes/ono-sendai/tactical.nix;
  };

  themeVariants = lib.unique (
    lib.flatten (lib.mapAttrsToList (_: theme: lib.attrNames theme) themes)
  );

  currentTheme = themes.${cfg.theme}.${cfg.variant};
in
{
  options.hyper-modern-nixos.themes = {
    enable = mkEnableOption "hyper-modern theming system" // {
      default = true;
    };

    theme = mkOption {
      type = types.enum (lib.attrNames themes);
      default = "ono-sendai-blue";
      description = "Theme family to use";
    };

    variant = mkOption {
      type = types.enum themeVariants;
      default = "chiba";
      description = "Theme variant within the family";
    };

    palette = mkOption {
      type = types.attrs;
      description = "The resolved base16 theme palette";
      internal = true;
      readOnly = true;
      default = currentTheme.palette;
    };
  };

  config = mkIf cfg.enable {
    # Pure color palette access for home-manager modules
    # No fonts, no stylix - just colors
  };
}
