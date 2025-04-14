# Cross-Platform Development Tooling

This repository contains a modular NixOS and Home-Manager configuration using the nixos-unified framework.

## Directory Structure

- `modules/home/` - Home-Manager modules organized by category:
  - `cloud/` - Cloud development tools (AWS, GCP, Terraform)
  - `dev/` - Development environments (Python, Ruby, TypeScript, etc.)
  - `llm/` - LLM integration tools
  - `nix/` - Nix configuration and development tools
  - `emacs/` - Emacs configuration
  - `fonts/` - Font configuration
  - `neovim/` - Neovim configuration
  - `shell/` - Shell environments (bash, cli tools, etc.)
  - `terminal/` - Terminal emulator configuration
  - `themes/` - Theme and styling configuration
  - `vscode/` - VSCode configuration
  - `secrets/` - Secrets management
  - `session/` - Session and SSH configuration
  - `wayland/` - Wayland desktop environments (Hyprland, Plasma)

## Usage

The configuration provides options to selectively enable or disable modules and features.

Example user configuration:

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
    hyprland.enable = true;   # Enable Hyprland
    plasma.enable = false;    # Disable Plasma
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

## Commands

```bash
just update  # Update flake locks
just check   # Validate configuration
just lint    # Format nix files
just run     # Activate the configuration
```
