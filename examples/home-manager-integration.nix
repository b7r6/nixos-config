# Example: Using development environments in home-manager
#
# This example shows how to import and use development environments
# in a home-manager configuration.
{ config, lib, pkgs, inputs, ... }:

{
  # Method 1: Import the entire suite of development environments
  imports = [
    # This imports all development environments at once
    inputs.dev-v4.homeManagerModules.dev-environments
  ];
  
  # Method 2: Selectively import specific environments
  # Uncomment these lines to use specific environments instead
  # imports = [
  #   inputs.dev-v4.homeManagerModules.python-dev
  #   inputs.dev-v4.homeManagerModules.rust-dev
  # ];
  
  # Configuration for dev environments
  programs = {
    # VSCode configuration that leverages the dev environment extensions
    vscode = {
      enable = true;
      # Extensions are automatically added by the imported dev environments
      # Additional extensions can be added here
      extensions = with pkgs.vscode-extensions; [
        # Project-specific extensions
        ms-vscode-remote.remote-ssh
      ];
    };
    
    # Neovim configuration that leverages the dev environments
    neovim = {
      enable = true;
      
      # Configure LSP for the languages in the imported dev environments
      plugins = with pkgs.vimPlugins; [
        nvim-lspconfig
        # LSP setup would reference the language servers installed by the dev environments
      ];
    };
  };
  
  # Additional home-manager configuration
  home = {
    # Base packages needed regardless of dev environments
    packages = with pkgs; [
      git
      direnv
      ripgrep
    ];
    
    # Set up .envrc template that uses the dev environments from flakes
    file.".config/direnv/templates/flake-dev.envrc".text = ''
      # Template for using dev-v4 environments in project directories
      # Usage: cp ~/.config/direnv/templates/flake-dev.envrc .envrc
      
      # Use flake-based development environment
      use flake
      
      # Additional project-specific environment setup
      # export PROJECT_ROOT=$PWD
    '';
  };
}