# ProArt P16 Configuration Testing in QEMU

This directory contains tools to test the ASUS ProArt P16 NixOS configuration in a QEMU virtual machine before deploying it to actual hardware.

## Testing Strategy

The testing environment simulates key aspects of the ProArt P16:

1. **High-DPI Display**: Configures a 3840x2400 resolution with proper DPI settings
2. **GPU Rendering**: Tests WebGPU rendering in WezTerm
3. **Berkeley Mono Font**: Tests font rendering at high DPI
4. **Configuration Files**: Uses similar configuration to what will be deployed

## Prerequisites

Ensure you have the following packages installed:

```bash
nix-shell -p qemu curl
```

## Testing Process

### Option 1: Use the Generic NixOS ISO (Fastest)

1. Run the VM with the default NixOS ISO:
   ```bash
   ./run-vm.sh
   ```

2. Once booted, log in as `root` without a password.

3. Create a quick test WezTerm configuration:
   ```bash
   # Install WezTerm
   nix-env -iA nixos.wezterm
   
   # Configure for Berkeley Mono
   mkdir -p ~/.config/wezterm
   nano ~/.config/wezterm/wezterm.lua
   
   # Add this basic config:
   local wezterm = require 'wezterm'
   local config = {}
   config.font = wezterm.font { family = 'Berkeley Mono' }
   config.dpi = 192.0
   return config
   
   # Test WezTerm
   wezterm
   ```

### Option 2: Build a Custom NixOS ISO (More Complete)

1. Build a custom ISO with our test configuration:
   ```bash
   ./build-iso.sh
   ```

2. Run the VM with our custom ISO:
   ```bash
   ./run-vm.sh
   ```

3. Once booted, log in with:
   - Username: `test`
   - Password: `test`

4. Launch WezTerm to test:
   ```bash
   wezterm
   ```

## What to Test

When testing the ProArt P16 configuration, focus on:

1. **Font Rendering**: Is Berkeley Mono clear and crisp?
2. **HiDPI Support**: Do UI elements scale correctly?
3. **Performance**: Is WebGPU rendering smooth?
4. **Key Bindings**: Do the custom shortcuts work?
5. **General UI**: Is the window decoration appropriate?

## Comparing with Real Hardware

While QEMU testing provides valuable insights, some aspects specific to the ProArt P16 can't be fully tested:

1. **Hybrid GPU**: The AMD + NVIDIA setup can't be fully emulated
2. **Power Management**: Battery optimizations can't be tested
3. **Hardware-specific drivers**: Some drivers are specific to the laptop

## Test Results Collection

When running tests, document your observations in a `test-results.md` file:

```bash
# Create test results file
touch test-results.md
nano test-results.md
```

## Transitioning to Real Hardware

After successful testing, you can deploy to your ProArt P16 using:

```bash
# From nixos-config main directory
sudo nixos-rebuild switch --flake .#proart
``` 