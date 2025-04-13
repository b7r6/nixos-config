# Bridge module that connects the old home-manager modules with the new flake modules
# This allows existing configurations to benefit from the new flake modules
{ config, lib, pkgs, ... }:

let
  # Check if we have access to the dev-environments
  hasDevEnvironments = pkgs ? dev-environments;
  
  # Get packages from dev environments if available, otherwise use empty lists
  pythonPackages = if hasDevEnvironments && pkgs.dev-environments ? python 
                   then pkgs.dev-environments.python.packages else [];
  rustPackages = if hasDevEnvironments && pkgs.dev-environments ? rust 
                then pkgs.dev-environments.rust.packages else [];
  typescriptPackages = if hasDevEnvironments && pkgs.dev-environments ? typescript 
                      then pkgs.dev-environments.typescript.packages else [];
  dotnetPackages = if hasDevEnvironments && pkgs.dev-environments ? dotnet 
                  then pkgs.dev-environments.dotnet.packages else [];
in
{
  config = lib.mkIf config.dev.enable {
    # Add packages from flake modules if available
    home.packages = lib.concatLists [
      (lib.optionals (config.dev.python.enable && hasDevEnvironments) pythonPackages)
      (lib.optionals (config.dev.rust.enable && hasDevEnvironments) rustPackages)
      (lib.optionals (config.dev.typescript.enable && hasDevEnvironments) typescriptPackages)
      (lib.optionals (config.dev.dotnet.enable && hasDevEnvironments) dotnetPackages)
    ];
  };
}