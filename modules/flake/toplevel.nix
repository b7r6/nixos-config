{ inputs, ... }:
{
  debug = true;

  imports = [
    inputs.nixos-unified.flakeModules.default
    inputs.nixos-unified.flakeModules.autoWire
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

      # For 'nix fmt'
      formatter = pkgs.nixfmt-rfc-style;

      # Enables 'nix run' to activate.
      packages.default = self'.packages.activate;
    };
}
