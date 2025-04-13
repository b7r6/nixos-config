{ inputs, ... }:
{
  debug = true;
  
  imports = [
    inputs.nixos-unified.flakeModules.default
    inputs.nixos-unified.flakeModules.autoWire
    
    # Development environment modules - temporarily disabled
    # ./dev-environments.nix
    ./devshell.nix
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
      
      # Simple dev shell
      devShells.default = pkgs.mkShell {
        name = "dev-v4";
        packages = with pkgs; [
          # Just a few basic packages
          git
          jq
          ripgrep
          fd
        ];
        
        shellHook = ''
          echo "Dev-v4 shell activated"
        '';
      };
    };
}
