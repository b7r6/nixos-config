{
  description = "ProArt P16 NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    
    # Root flake
    nixos-config.url = "path:///home/b7r6/nixos-config";
    nixos-config.inputs.nixpkgs.follows = "nixpkgs";
    nixos-config.inputs.home-manager.follows = "home-manager";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nixos-config, ... }:
    {
      nixosConfigurations = {
        "proart-p16" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          
          modules = [
            # Include system configuration
            ./configuration/system.nix
            
            # Import modules from root flake
            nixos-config.nixosModules.emacs
            nixos-config.nixosModules.docker
            nixos-config.nixosModules.tmux
            nixos-config.nixosModules.refind
            
            # Add Home Manager support
            home-manager.nixosModules.home-manager
            {
              # Home Manager configuration
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { 
                inherit self inputs;
                flake = inputs;
              };
              home-manager.users.b7r6 = import ./configuration/home.nix;
            }
          ];
          
          specialArgs = { 
            inherit self inputs;
            flake = inputs;
          };
        };
      };
      
      # Expose specialized development shells by importing from root flake
      devShells.x86_64-linux = nixos-config.devShells.x86_64-linux // {
        # Add system-specific overlays or customizations
        proart-dev = nixpkgs.legacyPackages.x86_64-linux.mkShell {
          name = "proart-dev";
          buildInputs = with nixpkgs.legacyPackages.x86_64-linux; [
            # ProArt P16 specific development tools
            nixos-config.packages.x86_64-linux.emacs-development
          ];
          shellHook = ''
            echo "ProArt P16 Development Environment"
          '';
        };
      };
    };
} 