# Emacs Development Module

This Nix module provides a comprehensive Emacs development environment with special focus on Emacs Lisp development.

## Features

- **Dedicated Development Shell**: Special environment for Emacs Lisp development
- **Password Store Integration**: Seamless integration with `pass` for secure credential management
- **IDE Features**: Syntax highlighting, completion, linting, and debugging for Emacs Lisp
- **Project Templates**: Ready-made Emacs Lisp package template
- **Home Manager Integration**: Automatically configures Home Manager (optional)

## Usage

### Basic Configuration

```nix
# In your configuration.nix
{ config, lib, pkgs, ... }:
{
  imports = [ 
    # Other imports...
    ./modules/home/emacs
  ];

  programs.emacs-with-devshell = {
    enable = true;
    # Include additional packages
    extraPackages = [
      "company" "magit" "projectile" "counsel"
      # Your preferred packages...
    ];
  };
}
```

### Development Shell

Once configured, you can enter the development shell:

```bash
# Enter the development shell
nix develop .#emacs

# Or directly edit an Emacs Lisp file
emacs-dev my-package.el
```

### File Structure

The module sets up the following file structure:

```
~/.emacs.d/
  ├── elisp-project-template/   # Template for Emacs Lisp projects
  │   ├── template-package.el   # Main package file template
  │   ├── test/                 # Test directory
  │   │   └── template-package-test.el
  │   ├── Makefile              # Build system
  │   ├── README.md             # Documentation
  │   └── .gitignore            # Git ignore file
  └── ...

~/.local/
  ├── bin/
  │   └── el-edit               # Helper script to edit .el files
  └── share/
      └── applications/
          └── emacs-dev.desktop # Desktop entry
```

## Key Bindings in Development Environment

The development environment provides these useful key bindings:

| Key Binding | Function |
|-------------|----------|
| `C-c b` | Byte-compile current buffer |
| `C-c c` | Check elisp package (lint) |
| `C-c e d` | Debug function with edebug |
| `C-c d e` | Toggle debug-on-error |
| `C-c v` | Split window with Elisp documentation |
| `C-c p p` | Copy password (pass integration) |
| `C-c p g` | Generate password (pass integration) |

## Password Store Integration

When `includePassModule` is enabled (default), the environment integrates with `pass`:

- Automatically sets up auth-source for password-store
- Configures keybindings for password management
- Installs necessary Emacs packages for `pass` integration

## Advanced Configuration

```nix
programs.emacs-with-devshell = {
  enable = true;
  # Don't configure Home Manager
  includeHomeManager = false;
  # Disable pass integration
  includePassModule = false;
  # Add custom development packages
  extraDevPackages = with pkgs; [
    emacs-lsp-booster
    # Other useful packages...
  ];
};
```

## Creating an Emacs Lisp Package

1. Enter the development shell: `nix develop .#emacs`
2. Copy the template: `cp -r ~/.emacs.d/elisp-project-template ~/my-package`
3. Replace `template-package` with your package name in all files
4. Edit with the specialized environment: `emacs-dev ~/my-package/my-package.el`
5. Use `C-c c` to check for package lint issues
6. Use `C-c b` to byte-compile your package

## Implementation Details

This module is implemented using the flake-parts pattern, providing:

- A per-system development environment with `mkPerSystemOption`
- Proper documentation for all options
- HOME isolation to avoid sandbox issues
- Reproducible builds with explicit dependencies

See `flake-module.nix` for implementation details.
