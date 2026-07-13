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
    flake.inputs.nix-index-database.homeModules.nix-index
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
    # ── Per-user nix.conf substituters (managed) ──────────────────────────────

    # b7r6 is a trusted-user, so the USER-level ~/.config/nix/nix.conf
    # substituters OVERRIDE the system ones for interactive `nix` commands. A
    # stale hand-edited file here was pointing at weyl-ai/hyprland cachix and
    # NOT the local cache — so `nix build` bypassed our cache. Manage it
    # declaratively to mirror the system: the local nativelink-nix-cache FIRST,
    # then the public caches. This file is now owned by home-manager, so it
    # can't drift again.
    #
    # Migrated off attic (localhost:8080/hypermodern) to nativelink
    # (127.0.0.1:50071/nix/main) to match the system move in 182a40d. The old
    # attic endpoint is dead, and being pinned here made every interactive `nix`
    # command hang retrying it. nativelink binds 127.0.0.1, so on hosts that
    # don't run it the endpoint is simply unreachable and nix falls through to
    # cache.nixos.org — same fall-through as before, minus the stale name.
    nix.package = lib.mkDefault pkgs.nix;

    nix.settings = {
      substituters = [
        "http://127.0.0.1:50071/nix/main"
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];

      trusted-public-keys = [
        "hypermodern:x+kBunu5nD1KOhzCIawyZeq8w0LV0GC6A7suIRoHTm8="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    home.packages = lib.mkIf cfg.development.enable (
      with pkgs;
      [
        nixd
        nixfmt
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
