# Test configuration for ProArt P16 in QEMU
{ config, pkgs, ... }:

{
  imports = [ <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix> ];

  # Basic networking
  networking.networkmanager.enable = true;
  networking.hostName = "proart-test-vm";
  
  # User setup with sudo access
  users.users.test = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" ];
    initialPassword = "test";
  };
  
  # Allow passwordless sudo for the test user
  security.sudo.wheelNeedsPassword = false;
  
  # X11 configuration with high-DPI settings
  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
    displayManager.defaultSession = "xfce";
    
    # HiDPI settings
    dpi = 192;
    
    # Enable touchpad support
    libinput.enable = true;
  };
  
  # Font configuration
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      (stdenv.mkDerivation {
        name = "berkeley-mono-test";
        src = /home/b7r6/berkeley-mono;
        installPhase = ''
          mkdir -p $out/share/fonts/opentype
          cp *.otf $out/share/fonts/opentype/
        '';
      })
    ];
    
    fontconfig = {
      defaultFonts = {
        monospace = [ "Berkeley Mono" ];
        sansSerif = [ "Berkeley Mono" ];
        serif = [ "Berkeley Mono" ];
      };
    };
  };
  
  # Install WezTerm
  environment.systemPackages = with pkgs; [
    wezterm
    firefox
    git
    vim
    htop
    curl
    wget
  ];
  
  # WezTerm configuration for the test user
  system.activationScripts.wezterm-config = ''
    mkdir -p /home/test/.config/wezterm
    cat > /home/test/.config/wezterm/wezterm.lua << 'EOL'
    local wezterm = require 'wezterm'
    local config = {}
    
    -- Use GPU rendering for better performance on high-DPI displays
    config.front_end = "WebGpu"
    
    -- Font configuration - Berkeley Mono optimized for high-DPI
    config.font = wezterm.font {
      family = 'Berkeley Mono',
      harfbuzz_features = {'calt=1', 'liga=1'},
    }
    config.font_size = 13.0
    
    -- High-DPI configuration
    config.dpi = 192.0
    config.freetype_load_target = "Light"
    config.freetype_render_target = "HorizontalLcd"
    
    -- Window appearance settings
    config.window_decorations = "RESIZE"
    config.window_padding = {
      left = 2,
      right = 2,
      top = 0,
      bottom = 0,
    }
    
    -- Default colors - Catppuccin Mocha theme
    config.color_scheme = 'Catppuccin Mocha'
    
    -- Performance optimizations
    config.animation_fps = 60
    config.max_fps = 120
    config.scrollback_lines = 10000
    
    return config
    EOL
    
    chown -R test:users /home/test/.config
  '';
  
  # Hardware acceleration
  hardware.opengl = {
    enable = true;
    driSupport = true;
  };
  
  # System version
  system.stateVersion = "24.05";
} 