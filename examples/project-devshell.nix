# Example: Using development environments in a project flake
#
# This example shows how to import and use development environments
# in a project's flake.nix to create consistent devShells.
{
  description = "Example project using dev-v4 environments";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Import our development environments flake
    # When using from your own project, use the github URL or a local path
    dev-v4 = {
      url = "github:username/dev-v4"; # Replace with actual repository
      # url = "path:/path/to/dev-v4";  # For local development
    };

    # Standard flake setup
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      dev-v4,
      ...
    }:
    flake-parts.lib.mkFlake { inherit self; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        # Import the development environments flake module
        dev-v4.flakeModules.dev-environments
      ];

      # Enable development environments
      dev-environments.enable = true;

      perSystem =
        {
          config,
          self',
          pkgs,
          system,
          ...
        }:
        let
          # Access the development environments directly
          pythonEnv = config.dev-environments.python;
          rustEnv = config.dev-environments.rust;
        in
        {
          # Create a devShell with Python and Rust environments
          devShells.default = pkgs.mkShell {
            name = "my-project";

            # Combine packages from multiple environments
            packages =
              pythonEnv.packages
              ++ rustEnv.packages
              ++ (with pkgs; [
                # Add project-specific packages
                postgresql
                redis
              ]);

            # Combine shell hooks
            shellHook = ''
              ${pythonEnv.shellHook}
              ${rustEnv.shellHook}

              echo "Project development environment activated"

              # Project-specific setup
              export DATABASE_URL="postgresql://localhost:5432/mydb"
            '';
          };

          # You can also create specialized shells for specific tasks
          devShells.python-only = pkgs.mkShell {
            name = "python-only";
            packages = pythonEnv.packages;
            shellHook = pythonEnv.shellHook;
          };
        };
    };
}
