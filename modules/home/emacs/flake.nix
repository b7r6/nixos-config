{
  description = "Emacs development environment with Emacs Lisp tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ./flake-module.nix
      ];
      
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      
      perSystem = { config, pkgs, system, ... }: {
        # Configure the Emacs development environment
        emacs-dev = {
          enable = true;
          
          # Default packages for Emacs Lisp development
          extraEmacsPackages = [
            "company"
            "magit"
            "projectile"
            "counsel"
            "which-key"
            "doom-themes"
            "doom-modeline"
            "all-the-icons"
            "paredit"
            "rainbow-delimiters"
            "flycheck"
            "flycheck-package"
            "helpful"
            "elisp-slime-nav"
            "package-lint"
          ];
          
          # Additional development tools
          elDevPackages = with pkgs; [
            git
            ripgrep
            fd
            gnumake
            emacs-all-the-icons-fonts
          ];
          
          # Enable password store support
          includePassModule = true;
        };
        
        # Default package is the Emacs development environment
        packages.default = config.emacs-dev.packages.emacs-development;
        
        # Make the shell available as the default shell
        devShells.default = config.devShells.emacs;
      };
      
      # Provide NixOS and Home Manager modules
      flake = {
        nixosModules.default = import ./default.nix;
        homeManagerModules.default = { config, lib, pkgs, ... }: {
          imports = [ ./flake-module.nix ];
          
          options.programs.emacs-elisp-dev = {
            enable = lib.mkEnableOption "Enable Emacs Lisp development tools";
            
            extraPackages = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "company" "magit" "projectile" "which-key"
                "paredit" "flycheck" "package-lint"
              ];
              description = "Extra Emacs packages to install";
            };
          };
          
          config = lib.mkIf config.programs.emacs-elisp-dev.enable {
            emacs-dev = {
              enable = true;
              extraEmacsPackages = config.programs.emacs-elisp-dev.extraPackages;
            };
            
            # Create helper script
            home.packages = [
              (pkgs.writeShellScriptBin "el-edit" ''
                #!/usr/bin/env bash
                if [ -z "$1" ]; then
                  echo "Usage: el-edit <filename.el>"
                  exit 1
                fi
                
                # Create file if it doesn't exist
                if [ ! -f "$1" ]; then
                  touch "$1"
                fi
                
                # Use emacs-dev to edit the file
                ''${EMACS_DEV:-emacs-dev} "$1"
              '')
            ];
          };
        };
      };
    };
} 