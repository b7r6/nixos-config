{ inputs, ... }:
{
  debug = true;

  imports = [
    inputs.nixos-unified.flakeModules.default
    inputs.nixos-unified.flakeModules.autoWire
    ./fmt.nix
  ];

  perSystem =
    {
      self',
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
          overlays = [ inputs.devshell.overlays.default ];
        };
      };

      packages.default = self'.packages.activate;
      packages.berkeley-mono = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
    };
}
