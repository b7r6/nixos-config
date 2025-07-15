{
  config,
  lib,
  ...
}:
let

  themes = {
    ono-sendai-blue = import ./palettes/ono-sendai-blue.nix;
    ono-sendai-tactical = import ./palettes/ono-sendai-tactical.nix;
  };

  themeVariants = lib.unique (
    lib.flatten (lib.mapAttrsToList (_: theme: lib.attrNames theme) themes)
  );

  currentTheme = themes.${cfg.theme}.${cfg.variant};
  cfg = config.hypermodern.nixos.themes;
in
{
  options.hypermodern.nixos.themes = {
    theme = lib.mkOption {
      type = lib.types.enum (lib.attrNames themes);
      default = "ono-sendai-blue";
      description = "theme family to use";
    };

    variant = lib.mkOption {
      type = lib.types.enum themeVariants;
      default = "chiba";
      description = "theme variant within the family";
    };

    palette = lib.mkOption {
      type = lib.types.attrs;
      description = "resolved `base16` theme palette";
      internal = true;
      readOnly = true;
      default = currentTheme.palette;
    };
  };
}
