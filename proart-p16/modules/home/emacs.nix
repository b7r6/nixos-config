# Emacs configuration with robust LSP support
{ config, lib, pkgs, flake, ... }:

let
  # Basic Emacs init.el that will be expanded by the user
  # This provides a solid foundation with good LSP support
  initEl = ''
    ;; Basic UI configuration
    (menu-bar-mode -1)
    (tool-bar-mode -1)
    (scroll-bar-mode -1)
    (column-number-mode t)
    (global-display-line-numbers-mode t)
    (setq inhibit-startup-screen t)
    
    ;; Package management
    (require 'package)
    (add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
    (package-initialize)
    
    ;; Use-package for cleaner config
    (require 'use-package)
    (setq use-package-always-ensure t)
    
    ;; Theme configuration
    (use-package doom-themes
      :config
      (load-theme 'doom-one t))
    
    ;; UI enhancements
    (use-package doom-modeline
      :init (doom-modeline-mode 1))
    
    (use-package all-the-icons
      :if (display-graphic-p))
    
    ;; Project management
    (use-package projectile
      :init
      (projectile-mode +1)
      :bind (:map projectile-mode-map
                  ("C-c p" . projectile-command-map)))
    
    ;; Completion framework
    (use-package vertico
      :init
      (vertico-mode))
    
    (use-package marginalia
      :init
      (marginalia-mode))
    
    (use-package consult
      :bind (("C-x b" . consult-buffer)
             ("C-x 4 b" . consult-buffer-other-window)
             ("C-c s" . consult-ripgrep)))
    
    ;; Tree-sitter configuration - improved to ensure it always works
    (use-package treesit
      :ensure nil  ;; Built into Emacs 29+
      :config
      ;; Set language sources for tree-sitter
      (setq treesit-language-source-alist
            '((bash "https://github.com/tree-sitter/tree-sitter-bash")
              (c "https://github.com/tree-sitter/tree-sitter-c")
              (c-sharp "https://github.com/tree-sitter/tree-sitter-c-sharp")
              (cpp "https://github.com/tree-sitter/tree-sitter-cpp")
              (css "https://github.com/tree-sitter/tree-sitter-css")
              (go "https://github.com/tree-sitter/tree-sitter-go")
              (html "https://github.com/tree-sitter/tree-sitter-html")
              (javascript "https://github.com/tree-sitter/tree-sitter-javascript")
              (json "https://github.com/tree-sitter/tree-sitter-json")
              (nix "https://github.com/nix-community/tree-sitter-nix")
              (python "https://github.com/tree-sitter/tree-sitter-python")
              (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
              (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
              (yaml "https://github.com/ikatyang/tree-sitter-yaml")))
      
      ;; Prefer tree-sitter modes when available
      (setq major-mode-remap-alist
            '((bash-mode . bash-ts-mode)
              (c-mode . c-ts-mode)
              (c++-mode . c++-ts-mode)
              (css-mode . css-ts-mode)
              (js-mode . js-ts-mode)
              (js-json-mode . json-ts-mode)
              (python-mode . python-ts-mode)
              (typescript-mode . typescript-ts-mode)
              (nix-mode . nix-ts-mode))))
    
    (use-package treesit-auto
      :after treesit
      :config
      (global-treesit-auto-mode))
    
    ;; LSP configuration with eglot - optimized and improved for reliability
    (use-package eglot
      :hook ((python-ts-mode . eglot-ensure)
             (python-mode . eglot-ensure)
             (rust-mode . eglot-ensure)
             (c-ts-mode . eglot-ensure)
             (c++-ts-mode . eglot-ensure)
             (c-mode . eglot-ensure)
             (c++-mode . eglot-ensure)
             (js-ts-mode . eglot-ensure)
             (js-mode . eglot-ensure)
             (typescript-ts-mode . eglot-ensure)
             (typescript-mode . eglot-ensure)
             (tsx-ts-mode . eglot-ensure)
             (nix-ts-mode . eglot-ensure)
             (nix-mode . eglot-ensure)
             (bash-ts-mode . eglot-ensure)
             (sh-mode . eglot-ensure))
      :config
      ;; Performance optimizations
      (setq eglot-events-buffer-size 0)         ; Disable events buffer
      (setq eglot-sync-connect nil)             ; Connect asynchronously
      (setq eglot-autoshutdown t)               ; Shutdown unused servers
      (setq eglot-extend-to-xref t)             ; Improve cross-references
      
      ;; Set up LSP server configurations
      (add-to-list 'eglot-server-programs
                   '((python-ts-mode python-mode) . ("pyright-langserver" "--stdio")))
      (add-to-list 'eglot-server-programs
                   '((nix-ts-mode nix-mode) . ("nil")))
      (add-to-list 'eglot-server-programs
                   '((bash-ts-mode sh-mode) . ("bash-language-server" "start")))
      (add-to-list 'eglot-server-programs
                   '((typescript-ts-mode tsx-ts-mode js-ts-mode js-mode) . ("typescript-language-server" "--stdio")))
      (add-to-list 'eglot-server-programs
                   '((c-ts-mode c++-ts-mode c-mode c++-mode) . ("clangd")))
      
      ;; Increase read/write limits for better performance with large files
      (setq read-process-output-max (* 3 1024 1024)) ; 3MB (from 4k default)
      
      ;; Fallback LSP servers if preferred not found
      (setq eglot-connect-timeout 10)
      (setq eglot-autoreconnect t)
      (setq eglot-confirm-server-initiated-edits nil) ; Trust server edits
      
      ;; Key bindings for LSP functionality
      :bind (:map eglot-mode-map
                  ("C-c l a" . eglot-code-actions)
                  ("C-c l r" . eglot-rename)
                  ("C-c l f" . eglot-format-buffer)
                  ("C-c l o" . eglot-format)
                  ("C-c l d" . eldoc)
                  ("C-c l R" . eglot-reconnect)
                  ("C-c l s" . eglot-shutdown)))
    
    ;; Company for completion with better settings
    (use-package company
      :hook (prog-mode . company-mode)
      :config
      (setq company-minimum-prefix-length 1)          ; Start completion immediately
      (setq company-idle-delay 0.1)                   ; Quick completion
      (setq company-selection-wrap-around t)          ; Wrap around to top
      (setq company-tooltip-align-annotations t)      ; Align annotations
      (setq company-tooltip-flip-when-above t)        ; Better tooltip position
      (setq company-tooltip-minimum-width 30)         ; Wider tooltip
      (setq company-dabbrev-downcase nil)             ; Preserve case
      :bind (:map company-active-map
                  ("C-n" . company-select-next)
                  ("C-p" . company-select-previous)
                  ("TAB" . company-complete-selection)
                  ("<tab>" . company-complete-selection)))
    
    ;; Format code on save
    (use-package apheleia
      :config
      (apheleia-global-mode +1)
      
      ;; Configure formatters for different languages
      (setf (alist-get 'python-ts-mode apheleia-mode-alist) '(black isort))
      (setf (alist-get 'python-mode apheleia-mode-alist) '(black isort))
      (setf (alist-get 'rust-mode apheleia-mode-alist) '(rustfmt))
      (setf (alist-get 'nix-ts-mode apheleia-mode-alist) '(nixpkgs-fmt))
      (setf (alist-get 'nix-mode apheleia-mode-alist) '(nixpkgs-fmt))
      (setf (alist-get 'typescript-ts-mode apheleia-mode-alist) '(prettier))
      (setf (alist-get 'tsx-ts-mode apheleia-mode-alist) '(prettier))
      (setf (alist-get 'js-ts-mode apheleia-mode-alist) '(prettier))
      (setf (alist-get 'typescript-mode apheleia-mode-alist) '(prettier))
      (setf (alist-get 'js-mode apheleia-mode-alist) '(prettier)))
    
    ;; Magit for git
    (use-package magit
      :bind ("C-x g" . magit-status))
    
    ;; Direnv integration for project environment
    (use-package direnv
      :config
      (direnv-mode))
    
    ;; Enable better key bindings
    (use-package which-key
      :config
      (which-key-mode)
      (setq which-key-idle-delay 0.3))
    
    ;; Key bindings
    (global-set-key (kbd "C-x C-b") 'ibuffer)
    (global-set-key (kbd "C-s") 'consult-line)
    
    ;; Basic editing improvements
    (global-auto-revert-mode 1)
    (electric-pair-mode 1)
    (show-paren-mode 1)
    (global-hl-line-mode 1)
    
    ;; Better file navigation
    (use-package dired
      :ensure nil
      :config
      (setq dired-listing-switches "-alh")
      (setq dired-dwim-target t))
    
    ;; Programming language support enhanced with tree-sitter modes
    (use-package markdown-mode)
    (use-package yaml-mode)
    (use-package json-mode)
    (use-package nix-mode)
    (use-package nix-ts-mode)
    (use-package rust-mode)
    (use-package python)
    (use-package typescript-mode)
    
    ;; Performance optimizations for large files
    (global-so-long-mode 1)        ; Better handling of long lines
    (setq gc-cons-threshold 100000000) ; 100MB (from 800KB default)
    (setq gc-cons-percentage 0.6)  ; More aggressive GC
    
    ;; Load external user configuration if exists
    (setq user-custom-file (expand-file-name "custom.el" user-emacs-directory))
    (when (file-exists-p user-custom-file)
      (load user-custom-file))
    
    ;; Setup native compilation if available
    (when (and (fboundp 'native-comp-available-p)
              (native-comp-available-p))
      (setq native-comp-async-report-warnings-errors nil)
      (setq native-comp-deferred-compilation t)
      (setq native-comp-speed 2)) ; Balance between compilation speed and optimization
    
    ;; Load user's personal configuration if it exists
    (let ((personal-init-file (expand-file-name "personal-config/init.el" user-emacs-directory)))
      (when (file-exists-p personal-init-file)
        (load-file personal-init-file)))
  '';
in
{
  options.emacs = {
    enable = lib.mkEnableOption "Enable Emacs with robust LSP support";
  };

  config = lib.mkIf config.emacs.enable {
    programs.emacs = {
      enable = true;
      
      # Use emacs 30+ with native compilation and wayland support
      package = pkgs.emacs30-pgtk;
      
      # Add all required packages for a solid LSP experience
      extraPackages = epkgs: with epkgs; [
        # UI enhancements
        all-the-icons
        all-the-icons-completion
        doom-modeline
        doom-themes
        nerd-icons
        nerd-icons-completion
        
        # Core packages
        bind-key
        consult
        diminish
        marginalia
        orderless
        use-package
        vertico
        which-key
        
        # Completion
        company
        corfu       # Modern completion UI
        cape        # Completion extensions
        
        # Project management
        projectile
        
        # LSP support
        eglot
        consult-eglot
        
        # Tree-sitter for better syntax highlighting
        treesit-auto
        treesit-grammars.with-all-grammars
        
        # Git integration
        magit
        diff-hl    # Highlight changed lines in gutter
        git-timemachine
        
        # Development environment integration
        direnv
        envrc
        
        # Code formatting
        apheleia
        format-all
        
        # Programming languages with tree-sitter support
        json-mode
        markdown-mode
        nix-mode
        nix-ts-mode
        python
        rust-mode
        typescript-mode
        yaml-mode
        
        # Nix-specific tools
        nixpkgs-fmt
        
        # Miscellaneous utilities
        rainbow-delimiters
        rainbow-mode
        yasnippet
        flycheck
        vterm
      ];
      
      # Basic configuration
      extraConfig = initEl;
    };
    
    # Install LSP servers and development tools
    home.packages = with pkgs; [
      # LSP servers
      nodePackages.typescript-language-server
      nodePackages.pyright
      nodePackages.bash-language-server
      rust-analyzer
      nixd          # Nix language server protocol
      clang-tools   # clangd for C/C++
      
      # Formatting tools
      black         # Python formatter
      isort         # Python import sorting
      nodePackages.prettier
      nixpkgs-fmt
      rustfmt
      shfmt         # Shell formatter
      
      # Tree-sitter grammar development
      tree-sitter
      
      # Development tools
      gcc
      gnumake
      ripgrep       # Required for projectile/consult
      fd            # Better find
      
      # Version control
      git
      
      # Misc utilities for Emacs
      sqlite        # For org-roam and other database needs
      graphviz      # For org-roam graphs
      emacs-lsp-booster # Speed up LSP communications
      wordnet       # For dictionary lookups
      
      # Dependencies for various language servers
      nodejs
      python3
    ];
    
    # Enable Emacs daemon for faster startup
    services.emacs = {
      enable = true;
      client.enable = true;
      defaultEditor = true;
      socketActivation.enable = true;
      
      # Additional arguments for the Emacs client
      client.arguments = [
        "-c"                       # Create a new frame
        "-a=\"\""                  # Start emacs if not running
      ];
    };
    
    # Native compilation support
    home.sessionVariables = {
      EMACS_NATIVE_COMP_DIR = "$HOME/.cache/emacs/eln-cache";
    };
    
    # Add desktop file for Emacs
    xdg.desktopEntries.emacs = {
      name = "Emacs";
      genericName = "Text Editor";
      comment = "Edit text";
      mimeType = [
        "text/english"
        "text/plain"
        "text/x-makefile"
        "text/x-c++hdr"
        "text/x-c++src"
        "text/x-chdr"
        "text/x-csrc"
        "text/x-java"
        "text/x-moc"
        "text/x-pascal"
        "text/x-tcl"
        "text/x-tex"
        "application/x-shellscript"
        "text/x-c"
        "text/x-c++"
      ];
      categories = [ "Development" "TextEditor" ];
      exec = "emacsclient -c -a emacs %F";
      icon = "emacs";
      terminal = false;
      type = "Application";
    };
    
    # Create a special directory for external init.el that won't be managed by Home Manager
    # You can place your personal init.el here and it will be loaded after the base config
    home.file.".emacs.d/personal-config/.keep".text = "";
  };
} 