# Main entry point for the ProArt P16 configuration
{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
  
  username = "b7r6"; # Default username
in
{
  # Flake outputs
  flake = {
    # NixOS configuration for ProArt P16
    nixosConfigurations.proart = self.nixos-unified.lib.mkLinuxSystem
      { home-manager = true; }
      {
        nixpkgs.hostPlatform = "x86_64-linux";
        
        imports = [
          # System configuration
          ./configuration/system.nix
          
          # Home-manager setup
          {
            home-manager.users.${username} = {
              imports = [ self.homeModules.default ];
              home.stateVersion = "24.05";
            };
          }
        ];
      };
      
    # Home-manager module
    homeModules.default = { ... }: {
      imports = [ ./configuration/home.nix ];
    };
  };
} 