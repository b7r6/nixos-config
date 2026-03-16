{
  flake,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.nix;
in
{
  imports = [
    flake.inputs.nix-index-database.hmModules.nix-index
  ];

  options.hyper-modern-nixos.nix = {
    enable = lib.mkEnableOption "Nix development tools and integration";

    development.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Nix development packages (nixd, nixfmt, statix, etc.)";
    };

    nix-index.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nix-index for command-not-found suggestions";
    };

    nixd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable nixd language server configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.mkIf cfg.development.enable (
      with pkgs;
      [
        nixd
        nixfmt-rfc-style
        manix
        statix
        treefmt
      ]
    );

    # nix-index for command-not-found suggestions
    programs.nix-index = lib.mkIf cfg.nix-index.enable {
      enable = true;
      enableBashIntegration = true;
    };

    # nixd language server configuration
    xdg.configFile."nixd/nixd.nix" = lib.mkIf cfg.nixd.enable {
      text = ''
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
    };
  };
}
