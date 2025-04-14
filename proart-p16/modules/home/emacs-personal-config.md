# Personal Emacs Configuration

This document explains how to keep your personal Emacs configuration separate from Home Manager while still benefiting from the Nix-managed packages and core configuration.

## How It Works

The main `emacs.nix` file has been updated to:

1. Provide a robust foundation with tree-sitter and eglot (LSP) support
2. Create a special directory at `~/.emacs.d/personal-config/` 
3. Look for and load `~/.emacs.d/personal-config/init.el` if it exists

## Setup Instructions

1. Copy your existing `init.el` to `~/.emacs.d/personal-config/init.el`:

```bash
mkdir -p ~/.emacs.d/personal-config
cp ~/path/to/your/existing/init.el ~/.emacs.d/personal-config/init.el
```

2. Your personal configuration will be loaded *after* the Nix-managed foundation, so you can:
   - Override settings from the base configuration
   - Add additional packages not included in the Nix configuration
   - Customize your environment without having to modify the Nix files

## Key Enhancements

The base configuration now includes:

- **emacs30-pgtk**: Latest Emacs with native Wayland support
- **Tree-sitter integration**: Improved syntax highlighting and code parsing
- **Robust eglot configuration**: Enhanced LSP support for many languages
- **Native compilation**: For better performance
- **Auto-formatting**: With apheleia for most common languages

## Adding Custom Packages

You can still add packages in your personal init.el using `use-package`. For example:

```elisp
;; Additional packages not included in the Nix configuration
(use-package org-roam
  :ensure t
  :config
  (setq org-roam-directory "~/org/roam")
  (org-roam-db-autosync-mode))
```

## Keeping Configurations Separate

This approach allows you to:

1. Benefit from the Nix-managed packages and system integration
2. Maintain your personal configuration outside of Nix
3. Version your personal configuration separately if desired
4. Easily transfer your personal settings between machines

Your personal configuration can be versioned in its own git repository if desired:

```bash
cd ~/.emacs.d/personal-config
git init
git add init.el
git commit -m "Initial personal configuration"
```

## Troubleshooting

If you encounter package-related issues:

- Check if the package is already provided by the Nix configuration
- Make sure you're not overriding critical settings needed by tree-sitter or eglot
- When in doubt, use `M-x describe-variable` and `M-x describe-function` to check what's defined 