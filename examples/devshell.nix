# Example of using the development environments in a project-specific flake
# This explores a potential direction without modifying existing code
{
  description = "Example project using dev-v4 development environments";
  
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    
    # Import the dev-v4 flake to access its development environments
    dev-v4 = {
      url = "path:/path/to/dev-v4";
      # or url = "github:username/dev-v4";
    };
  };
  
  outputs = { self, nixpkgs, systems, dev-v4, ... }:
    let
      # Helper function using nix-systems
      forEachSystem = systems.lib.forEachSystem;
    in
    {
      # Development shells that use the dev-v4 environments
      devShells = forEachSystem (system:
        let
          pkgs = nixpkgs.${system};
          
          # Access the dev environments from dev-v4
          devEnvironments = dev-v4.flakeModules.dev-environments.${system};
        in
        {
          # Python development shell
          default = pkgs.mkShell {
            name = "python-project";
            
            # Include packages from the Python environment
            packages = devEnvironments.python.packages ++ (with pkgs; [
              # Add project-specific packages
              poetry
              sqlite
            ]);
            
            # Set up project-specific environment
            shellHook = ''
              echo "Python development environment activated"
              # Project-specific setup here
            '';
          };
          
          # TypeScript development shell
          typescript = pkgs.mkShell {
            name = "typescript-project";
            
            # Include packages from the TypeScript environment
            packages = devEnvironments.typescript.packages ++ (with pkgs; [
              # Add project-specific packages
              nodePackages.pnpm
            ]);
            
            # Set up project-specific environment
            shellHook = ''
              echo "TypeScript development environment activated"
              # Project-specific setup here
            '';
          };
        }
      );
    };
}