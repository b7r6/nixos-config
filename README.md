# Cross-Platform Development Tooling

This repository contains a modular NixOS and Home-Manager configuration using the nixos-unified framework.

## Directory Structure

- `modules/home/` - Home-Manager modules organized by category:
  - `cloud/` - Cloud development tools (AWS, GCP, Terraform)
  - `dev/` - Development environments (Python, Ruby, TypeScript, etc.)
  - `llm/` - LLM integration tools
  - `nix/` - Nix configuration and development tools
  - `emacs/` - Emacs configuration
  - `neovim/` - Neovim configuration
  - `shell/` - Shell environments (bash, cli tools, etc.)
  - `terminal/` - Terminal emulator configuration
  - `themes/` - Theme and styling configuration
  - `vscode/` - VSCode configuration
  - `session/` - Session and SSH configuration
  - `wayland/` - Wayland desktop environments (Hyprland)

- `modules/flake/` - Flake modules that can be reused:
  - `dev-environments.nix` - Reusable development environments for various languages
  - `devshell.nix` - Dev shell configuration
  - `toplevel.nix` - Top-level flake module
  - `neovim.nix` - Neovim editor configuration

- `examples/` - Example configurations:
  - `devshell.nix` - Example project using dev environments in a devShell
  - `home-manager-integration.nix` - Example of using dev environments in home-manager

## Usage

The configuration provides options to selectively enable or disable modules and features.

### Home-Manager Configuration:

```nix
{ ... }:
{
  # Configure user identity
  me = {
    username = "youruser";
    fullname = "Your Full Name";
    email = "your.email@example.com";
  };

  # Configure wayland modules
  wayland = {
    # Enable or disable all wayland modules
    enable = true;
    
    # Configure specific desktop environments
    hyprland.enable = true;
  };
  
  # Configure development modules
  dev = {
    # Enable or disable all development modules 
    enable = true;
    
    # Configure specific languages
    python.enable = true;
    ruby.enable = false;
    typescript.enable = true;
    git.enable = true;
    systems.enable = true;
  };
}
```

### Development Environments

The repository now includes flake modules for development environments that can be:
1. Used directly in project-specific devShells
2. Integrated into home-manager configurations

This allows reusing the same development environment definitions across both your home environment and project-specific shells.

See the `examples/` directory for usage examples.

## Commands

```bash
just update  # Update flake locks
just check   # Validate configuration
just lint    # Format nix files
just run     # Activate the configuration
just dev     # Enter the development shell
```
