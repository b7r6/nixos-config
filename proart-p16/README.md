# ASUS ProArt P16 NixOS Configuration

A focused, streamlined NixOS configuration for the ASUS ProArt P16 laptop, built using the nixos-unified framework.

## Key Features

- **Optimized Kernel Settings**: Tailored for stability on the ASUS ProArt P16 hardware
- **Wayland + Hyprland + Hy3**: Modern, efficient desktop environment with tiling window management
- **Network Management**: Integrated Tailscale and Mullvad VPN for secure connectivity
- **System-wide Themes**: Consistent styling with Stylix across applications
- **Emacs**: Highly optimized Emacs configuration with robust LSP support
- **Cachix Integration**: Efficient binary cache usage

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/proart-p16.git
   cd proart-p16
   ```

2. Build and activate:
   ```bash
   just build   # Test build without activating
   just switch  # Activate the configuration
   ```

## Commands

This project includes a `justfile` with common commands:

- `just build` - Build the configuration
- `just switch` - Activate the configuration
- `just boot` - Set as default for next boot
- `just update` - Update flake lock file
- `just check` - Check configuration
- `just fmt` - Format Nix files
- `just gc` - Clean old generations
- `just generations` - List system generations

## Structure

- `configuration/` - System and home configurations
- `modules/` - Home-manager and NixOS modules
- `flake.nix` - Core flake definition
- `default.nix` - Main entry point
- `justfile` - Command shortcuts

## Customization

To customize this configuration:

1. Edit `configuration/hardware-configuration.nix` to match your hardware
2. Modify `configuration/system.nix` for system-wide settings
3. Adjust `configuration/home.nix` for user-specific settings
4. Update modules as needed in `modules/home/`

## About

This configuration is built on:

- [nixos-unified](https://github.com/srid/nixos-unified) - For flake structure
- [home-manager](https://github.com/nix-community/home-manager) - For user environment
- [stylix](https://github.com/danth/stylix) - For system-wide theming
- [Hyprland](https://github.com/hyprwm/Hyprland) - For window management
- [Hy3](https://github.com/outfoxxed/hy3) - For tiling layout 