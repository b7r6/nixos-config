{ ... }:
{
  # Create the nixd configuration file
  xdg.configFile."nixd/nixd.nix".text = ''
    {
      flake = {
        registry = [
          {
            from = { owner = "nixos"; repo = "nixpkgs"; }; 
            to = { type = "github"; owner = "nixos"; repo = "nixpkgs"; };
          }
          {
            from = { owner = "nix-community"; repo = "home-manager"; };
            to = { type = "github"; owner = "nix-community"; repo = "home-manager"; };
          }
        ];
      };
      
      nixpkgs.expr = ''''
        import
        "github:nixos/nixpkgs"
        { }
      '''';
            
      options = {
        nixos.expr = ''''
          (
            let
              pkgs = import "github:nixos/nixpkgs" { };
            in
            (pkgs.lib.evalModules {
              modules = (import "github:nixos/nixpkgs/nixos/modules/module-list.nix") ++ [
                (
                  { ... }:
                  {
                    nixpkgs.hostPlatform = builtins.currentSystem;
                  }
                )
              ];
            })
          ).options
        '''';
              
        home_manager.expr = ''''
          (
            let
              pkgs = import "github:nixos/nixpkgs" { };
              lib = import "github:nix-community/home-manager/modules/lib/stdlib-extended.nix" pkgs.lib;
            in
            (lib.evalModules {
              modules = (import "github:nix-community/home-manager/modules/modules.nix") {
                inherit lib pkgs;
                check = false;
              };
            })
          ).options
        '''';
      };
    }
  '';
}
