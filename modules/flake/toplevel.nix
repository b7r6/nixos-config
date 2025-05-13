{ inputs, ... }:
{
  debug = true;

  imports = [
    inputs.nixos-unified.flakeModules.default
    inputs.nixos-unified.flakeModules.autoWire

    # Development environment modules - temporarily disabled
    # ./dev-environments.nix
    # ./devshell.nix
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

        overlays = [ ];

        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };
      };

      formatter = pkgs.nixfmt-rfc-style;
      packages.default = self'.packages.activate;
    };
}
