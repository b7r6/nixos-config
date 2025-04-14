# Font configuration for system-wide Berkeley Mono support
{ config, lib, pkgs, ... }:

{
  options.fonts.berkeley-mono = {
    enable = lib.mkEnableOption "Enable Berkeley Mono font";
    path = lib.mkOption {
      type = lib.types.str;
      default = "~/Downloads/berkeley-mono";
      description = "Path to Berkeley Mono font directory";
    };
  };

  config = lib.mkIf config.fonts.berkeley-mono.enable {
    fonts.fontDir.enable = true;
    
    # Create a derivation for Berkeley Mono from local files
    home.file = {
      ".local/share/fonts/berkeley-mono" = {
        source = config.fonts.berkeley-mono.path;
        recursive = true;
      };
    };
    
    # Force font cache update
    home.activation.fontCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
      $DRY_RUN_CMD fc-cache -fr
    '';
    
    # Ensure font-related packages are installed
    home.packages = with pkgs; [
      fontconfig
      font-manager
    ];
    
    # Set default fonts system-wide
    gtk = {
      enable = true;
      font = {
        name = "Berkeley Mono";
        size = 11;
      };
    };
    
    # Configure for QT applications too
    qt = {
      enable = true;
      platformTheme = "gtk";
    };
  };
} 