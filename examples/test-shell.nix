# Test shell to validate dev environments
{ pkgs, config, ... }:

# This simulates what would be in a project's flake.nix
let
  # Reference to dev-environments if available
  devEnv = if config ? dev-environments then config.dev-environments else {};
  
  # Get Python environment if available
  pythonEnv = if devEnv ? python then devEnv.python else { 
    packages = [];
    description = "Fallback Python environment"; 
  };
  
  # Get TypeScript environment if available
  tsEnv = if devEnv ? typescript then devEnv.typescript else { 
    packages = [];
    description = "Fallback TypeScript environment"; 
  };
in
{
  # Create a shell that uses these environments
  devShells.test = pkgs.mkShell {
    name = "test-dev-environments";
    
    packages = 
      pythonEnv.packages ++
      tsEnv.packages ++
      (with pkgs; [
        # Additional project-specific packages
        jq
        ripgrep
      ]);
    
    shellHook = ''
      echo "Test shell for ${pythonEnv.description} and ${tsEnv.description}"
    '';
  };
}