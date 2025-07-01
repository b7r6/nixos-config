{ inputs, ... }:
{
  debug = true;

  imports = [
    inputs.nixos-unified.flakeModules.default
    inputs.nixos-unified.flakeModules.autoWire
    inputs.devshell.flakeModule
    ./fmt.nix
  ];

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

        overlays = [
          inputs.devshell.overlays.default
        ];
      };

      devshells.default.imports = [ (pkgs.devshell.importTOML ../../devshell.toml) ];
      devshells.secrets.imports = [ (pkgs.devshell.importTOML ../../secrets/devshell.toml) ];

      packages.default = self'.packages.activate;
      packages.berkeley-mono = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
    };
}
