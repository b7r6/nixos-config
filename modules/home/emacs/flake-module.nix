# Emacs module for flake-parts with development shell
{ lib, flake-parts-lib, ... }:

let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) types mkOption;
in
{
  options = {
    perSystem = mkPerSystemOption ({ config, pkgs, system, ... }: {
      options.emacs-dev = {
        enable = lib.mkEnableOption "Enable Emacs development module";
        
        package = mkOption {
          type = types.package;
          default = pkgs.emacs;
          description = "Emacs package to use";
          example = "pkgs.emacs-git";
        };
        
        emacsPackagesOverride = mkOption {
          type = types.functionTo types.attrs;
          default = _: {};
          description = "Function to override Emacs packages";
          example = ''epkgs: {
            inherit (epkgs.melpaPackages) vterm;
          }'';
        };
        
        extraEmacsPackages = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Extra Emacs packages to include";
          example = ''[ "company" "magit" "org" ]'';
        };
        
        elDevPackages = mkOption {
          type = types.listOf types.package;
          default = [];
          description = "Development packages for Emacs Lisp";
          example = "with pkgs; [ emacs-lsp-booster emacs-all-the-icons-fonts ]";
        };
        
        includePassModule = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to include the password-store module";
        };
      };
    });
  };
  
  config = {
    perSystem = { config, pkgs, system, ... }:
    let
      cfg = config.emacs-dev;
      
      # Emacs with all packages
      emacsWithPackages = (pkgs.emacsPackagesFor cfg.package).emacsWithPackages;
      
      # Function to build package list
      buildPackageList = epkgs:
        (map (name: epkgs.${name}) cfg.extraEmacsPackages) ++
        [
          # Base packages for Emacs Lisp development
          epkgs.paredit              # Structured editing for Lisp
          epkgs.rainbow-delimiters   # Color-code nested parentheses
          epkgs.flycheck             # Syntax checking
          epkgs.flycheck-package     # Lint elisp packages
          epkgs.highlight-defined    # Highlight known elisp symbols
          epkgs.macrostep            # Interactive macro expansion
          epkgs.elisp-slime-nav      # M-. navigation for elisp
          epkgs.package-lint         # Lint for package.el compliance
          epkgs.lisp-extra-font-lock # Better Lisp syntax highlighting
          epkgs.helpful              # Better help buffers
          
          # Tree-sitter support if available
          (epkgs.tree-sitter or epkgs.treesit)
          (epkgs.tree-sitter-langs or epkgs.treesit-langs)
        ] ++
        
        # Password store packages if enabled
        (lib.optionals cfg.includePassModule [
          epkgs.password-store     # Base pass.el
          epkgs.auth-source-pass   # Auth-source integration
          epkgs.pass               # Enhanced UI
          epkgs.password-store-otp # OTP support
        ]) ++
        
        # Add any custom overrides
        (builtins.attrValues (cfg.emacsPackagesOverride epkgs));
      
      # Build our final Emacs package with all dependencies
      emacsForDevelopment = emacsWithPackages buildPackageList;
      
      # Create a proper init.el for the dev shell
      initElDev = pkgs.writeText "init-dev.el" ''
        ;; Development environment for Emacs Lisp
        
        ;; Basic Emacs configuration
        (setq inhibit-startup-screen t)
        (menu-bar-mode -1)
        (tool-bar-mode -1)
        (scroll-bar-mode -1)
        (column-number-mode 1)
        
        ;; Emacs Lisp development setup
        (require 'paredit)
        (require 'rainbow-delimiters)
        (require 'highlight-defined)
        (require 'elisp-slime-nav)
        (require 'package-lint)
        (require 'flycheck)
        
        ;; Setup hooks for Emacs Lisp mode
        (add-hook 'emacs-lisp-mode-hook 'paredit-mode)
        (add-hook 'emacs-lisp-mode-hook 'rainbow-delimiters-mode)
        (add-hook 'emacs-lisp-mode-hook 'highlight-defined-mode)
        (add-hook 'emacs-lisp-mode-hook 'elisp-slime-nav-mode)
        (add-hook 'emacs-lisp-mode-hook 'flycheck-mode)
        
        ;; Better help
        (require 'helpful)
        (global-set-key (kbd "C-h f") #'helpful-callable)
        (global-set-key (kbd "C-h v") #'helpful-variable)
        (global-set-key (kbd "C-h k") #'helpful-key)
        
        ;; Debugging setup
        (setq debug-on-error nil)
        (global-set-key (kbd "C-c d e") 'toggle-debug-on-error)
        
        ;; Indentation setup for .el files
        (setq-default indent-tabs-mode nil)
        (setq lisp-indent-function 'lisp-indent-function)
        
        ;; Automatic parenthesis matching
        (show-paren-mode 1)
        
        ;; Byte-compilation helpers
        (defun byte-compile-current-buffer ()
          "Byte-compile the current buffer's file."
          (interactive)
          (byte-compile-file buffer-file-name))
        
        (global-set-key (kbd "C-c b") 'byte-compile-current-buffer)
        
        ;; Auto-reload changes to .el files
        (global-auto-revert-mode 1)
        
        ;; Edebug setup with convenient key
        (global-set-key (kbd "C-c e d") 'edebug-defun)
        
        ;; Package development help
        (defun check-elisp-package ()
          "Run package-lint and flycheck on the current buffer."
          (interactive)
          (package-lint-current-buffer)
          (flycheck-buffer))
        
        (global-set-key (kbd "C-c c") 'check-elisp-package)
        
        ;; Show function arglist and doc in minibuffer
        (add-hook 'emacs-lisp-mode-hook 'eldoc-mode)
        
        ;; Clean view with only code and documentation visible
        (defun elisp-coding-view ()
          "Configure window for optimal elisp coding."
          (interactive)
          (delete-other-windows)
          (split-window-right)
          (other-window 1)
          (info "elisp")
          (other-window 1))
        
        (global-set-key (kbd "C-c v") 'elisp-coding-view)
        
        ;; Include password-store setup if enabled
        ${lib.optionalString cfg.includePassModule ''
        ;; Password Store (pass) integration
        (require 'auth-source-pass)
        (auth-source-pass-enable)
        (setq auth-sources '(password-store))
        
        ;; Key bindings for password-store
        (global-set-key (kbd "C-c p p") 'password-store-copy)
        (global-set-key (kbd "C-c p g") 'password-store-generate)
        ''}
        
        ;; Message to confirm init.el was properly loaded
        (message "Emacs Lisp development environment loaded!")
      '';
      
      # Create a shell script to launch Emacs with our config
      emacsDev = pkgs.writeShellScriptBin "emacs-dev" ''
        export EMACSLOADPATH=""  # Clear to avoid conflicts
        exec ${emacsForDevelopment}/bin/emacs --no-init-file --load ${initElDev} "$@"
      '';
      
    in lib.mkIf cfg.enable {
      # Expose the configured Emacs package
      packages.emacs-development = emacsForDevelopment;
      
      # Provide a development shell for Emacs Lisp
      devShells.emacs = pkgs.mkShell {
        name = "emacs-dev-shell";
        
        # Include our customized Emacs and launcher
        buildInputs = [
          emacsForDevelopment
          emacsDev
        ] ++ cfg.elDevPackages ++ (with pkgs; [
          # Basic development tools
          git
          ripgrep
          fd
          
          # Emacs Lisp specific tools
          (aspellWithDicts (ds: with ds; [en en-computers en-science]))
          
          # Password store tools if enabled
          (lib.optional cfg.includePassModule pkgs.pass)
          (lib.optional cfg.includePassModule pkgs.pinentry-emacs)
        ]);
        
        # Shell hook to set up the environment
        shellHook = ''
          export PROJECT_ROOT=$PWD
          
          # Ensure XDG dirs are set
          export XDG_CONFIG_HOME=''${XDG_CONFIG_HOME:-$HOME/.config}
          export XDG_DATA_HOME=''${XDG_DATA_HOME:-$HOME/.local/share}
          export XDG_CACHE_HOME=''${XDG_CACHE_HOME:-$HOME/.cache}
          
          # Setup for password-store if enabled
          ${lib.optionalString cfg.includePassModule ''
          export PASSWORD_STORE_DIR=''${PASSWORD_STORE_DIR:-$HOME/.password-store}
          export PASSWORD_STORE_CLIP_TIME=45
          export PASSWORD_STORE_GENERATED_LENGTH=30
          
          # Set pinentry to use Emacs
          export PINENTRY_USER_DATA="USE_CURSES=0"
          ''}
          
          echo "Emacs Lisp development environment loaded."
          echo "Run 'emacs-dev your-file.el' to edit with the dev configuration."
        '';
      };
      
      # Provide a check to verify the Emacs installation works
      checks.emacs-dev = pkgs.runCommand "check-emacs-dev" {
        buildInputs = [ emacsForDevelopment ];
      } ''
        # Set HOME to $TMPDIR to avoid permission issues
        export HOME=$TMPDIR
        
        # Verify Emacs starts correctly
        emacs --batch --eval "(progn (message \"Emacs started successfully\") (kill-emacs 0))" || {
          echo "Emacs failed to start in batch mode"
          exit 1
        }
        
        # Verify required packages are available
        emacs --batch --eval "(require 'paredit)" || {
          echo "Missing package: paredit"
          exit 1
        }
        
        emacs --batch --eval "(require 'flycheck)" || {
          echo "Missing package: flycheck"
          exit 1
        }
        
        ${lib.optionalString cfg.includePassModule ''
        emacs --batch --eval "(require 'password-store)" || {
          echo "Missing package: password-store"
          exit 1
        }
        ''}
        
        touch $out
      '';
    };
  };
} 