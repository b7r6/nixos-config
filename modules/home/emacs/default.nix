# Emacs module for NixOS configuration
{ config, lib, pkgs, ... }:

{
  imports = [ ./flake-module.nix ];
  
  options.programs.emacs-with-devshell = {
    enable = lib.mkEnableOption "Enable Emacs with development tools";
    
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "company" "magit" "projectile" "counsel" "which-key"
        "doom-themes" "doom-modeline" "all-the-icons" "treemacs"
        "markdown-mode" "yaml-mode" "nix-mode" "direnv"
        "org" "org-roam" "expand-region" "multiple-cursors"
      ];
      description = "Extra Emacs packages to install";
    };
    
    includeHomeManager = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to automatically configure Home Manager for Emacs";
    };
    
    includePassModule = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to include password-store support";
    };
    
    extraDevPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Extra packages to include in the development shell";
    };
  };
  
  config = lib.mkIf config.programs.emacs-with-devshell.enable {
    # Enable the Emacs development module
    emacs-dev = {
      enable = true;
      extraEmacsPackages = config.programs.emacs-with-devshell.extraPackages;
      includePassModule = config.programs.emacs-with-devshell.includePassModule;
      elDevPackages = config.programs.emacs-with-devshell.extraDevPackages;
    };
    
    # Home Manager configuration if enabled
    home-manager.users = lib.mkIf config.programs.emacs-with-devshell.includeHomeManager (
      let
        username = config.myself.username or "b7r6";
      in {
        ${username} = { pkgs, ... }: {
          # Install Emacs
          programs.emacs = {
            enable = true;
            package = pkgs.emacs;
            extraPackages = epkgs: 
              (map (name: epkgs.${name}) config.programs.emacs-with-devshell.extraPackages);
          };
          
          # Create desktop entry for the Emacs dev environment
          home.file.".local/share/applications/emacs-dev.desktop" = {
            text = ''
              [Desktop Entry]
              Name=Emacs Development
              GenericName=Text Editor (Dev Mode)
              Comment=Edit text with specialized Emacs Lisp development environment
              Exec=emacs-dev %F
              Icon=emacs
              Type=Application
              Terminal=false
              Categories=Development;TextEditor;
              Keywords=Text;Editor;Lisp;Elisp;
              StartupWMClass=Emacs
              MimeType=text/plain;text/x-chdr;text/x-csrc;text/x-c++hdr;text/x-c++src;text/x-java;text/x-dsrc;text/x-pascal;text/x-perl;text/x-python;application/x-php;application/x-httpd-php3;application/x-httpd-php4;application/x-httpd-php5;application/xml;text/html;text/css;text/x-sql;text/x-diff;x-directory/normal;inode/directory;
            '';
            executable = true;
          };
          
          # Add convenience scripts
          home.file.".local/bin/el-edit" = {
            text = ''
              #!/usr/bin/env bash
              if [ -z "$1" ]; then
                echo "Usage: el-edit <filename.el>"
                exit 1
              fi
              
              # Create file if it doesn't exist
              if [ ! -f "$1" ]; then
                touch "$1"
              fi
              
              emacs-dev "$1"
            '';
            executable = true;
          };
          
          # Create elisp project directory template
          home.file.".emacs.d/elisp-project-template" = {
            source = pkgs.runCommand "elisp-project-template" {} ''
              mkdir -p $out
              
              # Main source file
              cat > $out/template-package.el << EOF
              ;;; template-package.el --- Description -*- lexical-binding: t; -*-
              
              ;; Copyright (C) $(date +%Y) $(whoami)
              
              ;; Author: $(whoami)
              ;; Keywords: lisp
              ;; Version: 0.0.1
              ;; Package-Requires: ((emacs "27.1"))
              
              ;;; Commentary:
              
              ;; A description of the package.
              
              ;;; Code:
              
              (defgroup template-package nil
                "Settings for template-package."
                :group 'tools)
              
              (defcustom template-package-variable nil
                "Example variable."
                :type 'boolean
                :group 'template-package)
              
              ;;;###autoload
              (defun template-package-function ()
                "Example function."
                (interactive)
                (message "Hello from template-package!"))
              
              (provide 'template-package)
              ;;; template-package.el ends here
              EOF
              
              # Test file
              mkdir -p $out/test
              cat > $out/test/template-package-test.el << EOF
              ;;; template-package-test.el --- Tests for template-package -*- lexical-binding: t; -*-
              
              (require 'ert)
              (require 'template-package)
              
              (ert-deftest template-package-test-basic ()
                "Test that template-package works."
                (should t))
              
              (provide 'template-package-test)
              ;;; template-package-test.el ends here
              EOF
              
              # Makefile
              cat > $out/Makefile << EOF
              .PHONY: test compile clean
              
              EMACS ?= emacs
              EFLAGS = --batch -l ert
              
              TESTFILES = \$(wildcard test/*test.el)
              ELFILES = \$(wildcard *.el)
              ELCFILES = \$(patsubst %.el,%.elc,\$(ELFILES))
              
              test: \$(TESTFILES)
              	\$(EMACS) \$(EFLAGS) -l \$(TESTFILES) -f ert-run-tests-batch-and-exit
              
              compile: \$(ELCFILES)
              
              %.elc: %.el
              	\$(EMACS) --batch -f batch-byte-compile \$<
              
              clean:
              	rm -f \$(ELCFILES)
              EOF
              
              # README
              cat > $out/README.md << EOF
              # template-package
              
              ## Summary
              
              Brief description of what this package does.
              
              ## Installation
              
              ### Manual
              
              Download this repository and add it to your load-path:
              
              \`\`\`elisp
              (add-to-list 'load-path "/path/to/template-package")
              (require 'template-package)
              \`\`\`
              
              ### With use-package
              
              \`\`\`elisp
              (use-package template-package
                :load-path "/path/to/template-package")
              \`\`\`
              
              ## Usage
              
              \`\`\`elisp
              (template-package-function)
              \`\`\`
              
              ## Development
              
              - Run tests: \`make test\`
              - Byte compile: \`make compile\`
              - Clean .elc files: \`make clean\`
              EOF
              
              # .gitignore
              cat > $out/.gitignore << EOF
              # Compiled
              *.elc
              
              # Packaging
              .cask
              
              # Backup files
              *~
              \#*\#
              .\#*
              
              # Undo-tree save-files
              *.~undo-tree
              EOF
            '';
            recursive = true;
          };
          
          # Password store setup if enabled
          programs.password-store = lib.mkIf config.programs.emacs-with-devshell.includePassModule {
            enable = true;
            package = pkgs.pass;
          };
          
          home.packages = with pkgs; [
            # Tools for elisp
            emacs-all-the-icons-fonts
          ];
        };
      }
    );
    
    # System packages
    environment.systemPackages = with pkgs; [
      # Make emacs-dev available system-wide
      config.emacs-dev.packages.emacs-development
      
      # Create a script to launch the emacs dev environment
      (writeShellScriptBin "emacs-dev" ''
        # Check if we can use the home manager version
        if [ -x "$HOME/.nix-profile/bin/emacs-dev" ]; then
          exec "$HOME/.nix-profile/bin/emacs-dev" "$@"
        else
          # Fall back to system version
          export EMACSLOADPATH=""
          emacs=$(command -v emacs)
          init_el="${config.emacs-dev.packages.emacs-development}/share/emacs/site-lisp/init-dev.el"
          exec "$emacs" --no-init-file --load "$init_el" "$@"
        fi
      '')
    ];
  };
}
