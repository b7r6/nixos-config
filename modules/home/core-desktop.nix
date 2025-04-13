# Core desktop environment with sensible defaults
# Focused on providing a solid desktop experience separate from development tools
{ config, lib, pkgs, ... }:

with lib;
let 
  cfg = config.core-desktop;
in {
  options.core-desktop = {
    enable = mkEnableOption "Core desktop environment defaults";
    
    # Shell and terminal configuration
    shell = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable shell configuration";
      };
    };
    
    # Terminal emulator preferences
    terminal = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable terminal emulator configuration";
      };
      
      # Use the same options that are already defined
      lowEndHardware = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to optimize for low-end hardware";
      };
    };
    
    # Text editors (Neovim/Emacs)
    editors = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable text editor configurations";
      };
      
      neovim = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Neovim configuration";
        };
      };
      
      emacs = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Enable Emacs configuration";
        };
      };
    };
    
    # Theming and fonts
    themes = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable theming and font configuration";
      };
    };
  };
  
  config = mkIf cfg.enable {
    # Set up most modules without the development tools
    imports = [
      # User identity
      ./me.nix
      
      # Terminal tools (imported conditionally)
      ./shell
      ./terminal
      
      # Editor configs (imported conditionally)
      (mkIf (cfg.editors.enable && cfg.editors.neovim.enable) ./neovim)
      (mkIf (cfg.editors.enable && cfg.editors.emacs.enable) ./emacs)
      
      # Theming (imported conditionally)
      (mkIf cfg.themes.enable ./themes)
      
      # Session management
      ./session
      
      # Desktop environment
      ./desktop
      ./wayland
    ];
    
    # Enable necessary configs by default
    terminals.lowEndHardware = cfg.terminal.lowEndHardware;
    
    # Set common environment variables
    home.sessionVariables = {
      EDITOR = "nvim"; 
      VISUAL = "nvim";
      PAGER = "less -FirSwX";
    };
    
    # Basic packages for daily use
    home.packages = with pkgs; [
      # Essentials
      curl
      wget
      
      # Archive tools
      zip
      unzip
      p7zip
      
      # Utilities
      ripgrep 
      fd
      tree
      jq
    ];
  };
}