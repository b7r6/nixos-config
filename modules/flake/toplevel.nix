{ inputs, ... }:
{
  debug = true;

  imports = [
    inputs.nixos-unified.flakeModules.default
    inputs.nixos-unified.flakeModules.autoWire
    inputs.devshell.flakeModule
    inputs.nix-compile.flakeModules.default
    ./fmt.nix
    ./themes
    # ./impure-variants.nix  # TODO: needs different approach to avoid recursion
  ];

  # nix-compile static analysis configuration
  nix-compile = {
    enable = true;
    profile = "strict";
    layout = "none";
    paths = [
      "modules"
      "configurations"
    ];
    pre-commit.enable = true;
  };

  perSystem =
    {
      self',
      config,
      pkgs,
      system,
      ...
    }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;

        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };

        overlays = [ inputs.devshell.overlays.default ];
      };

      devshells.default.imports = [ (pkgs.devshell.importTOML ../../devshell.toml) ];
      devshells.secrets.imports = [ (pkgs.devshell.importTOML ../../secrets/devshell.toml) ];

      packages.default = self'.packages.activate;
      packages.berkeley-mono = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
    };
}
