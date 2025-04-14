# Main Home Manager configuration for ProArt P16
{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
  rootConfig = flake.nixos-config;
in
{
  # Import our modules
  imports = [
    ../modules/home/hyprland.nix
    ../modules/home/themes.nix
    ../modules/home/fonts.nix
    ../modules/home/wezterm.nix
    ../modules/home/xremap.nix
    ../modules/home/hyprpanel.nix
    ../modules/home/keyboard.nix
    ../modules/home/firefox.nix    # Firefox configuration
    ../modules/home/vscode.nix     # VSCode configuration
    ../modules/home/cursor.nix     # Cursor theme configuration
    ../modules/home/tmux.nix       # TMux configuration
    # Use emacs module from the root flake
    rootConfig.nixosModules.emacs
  ];

  # User identification
  me = {
    username = "b7r6";
    fullname = "b7r6";
    email = "b7r6@b7r6.net";
  };

  # Enable and configure modules
  wayland.hyprland.enable = true;
  # Enable new Emacs with dev shell
  programs.emacs-with-devshell = {
    enable = true;
    extraPackages = [
      "company" "magit" "projectile" "counsel" "which-key"
      "doom-themes" "doom-modeline" "all-the-icons" "treemacs"
      "markdown-mode" "yaml-mode" "nix-mode" "direnv" "eglot"
      "org" "org-roam" "expand-region" "multiple-cursors"
      "nerd-icons" "nerd-icons-completion" "treesit-auto"
      "apheleia" "vertico" "consult" "orderless" "marginalia"
      "vterm" "format-all" "flycheck" "rainbow-delimiters"
      "rainbow-mode" "paredit" "paredit-everywhere"
    ];
    extraDevPackages = with flake.inputs.nixpkgs.legacyPackages.x86_64-linux; [
      emacs-all-the-icons-fonts
      emacs-lsp-booster
    ];
    includePassModule = true;
  };
  themes.enable = true;
  fonts.berkeley-mono = {
    enable = true;
    path = "/home/b7r6/berkeley-mono";
  };
  programs.wezterm-proart.enable = true;
  services.xremap.enable = true;
  services.hyprpanel.enable = true;
  keyboard.enable = true;
  firefox.enable = true;           # Enable Firefox with custom settings
  vscode.enable = true;            # Enable VSCode with custom settings
  cursor = {                       # Enable cursor theme with custom settings
    enable = true;
    theme = "Bibata-Modern-Ice";  # Use Bibata cursor theme
    size = 24;                    # Medium-sized cursor
  };
  programs.tmux-config.enable = true;  # Enable tmux configuration

  # Environment variables for improved Wayland experience
  home.sessionVariables = {
    # Wayland specifics
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland";
    GDK_BACKEND = "wayland";
    WLR_NO_HARDWARE_CURSORS = "1";
    
    # Hybrid GPU support
    GBM_BACKEND = "nvidia-drm"; 
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    LIBVA_DRIVER_NAME = "nvidia";
    WLR_DRM_DEVICES = "/dev/dri/card0"; # Use AMD dGPU
    
    # Ensure fonts are correctly configured
    FONTCONFIG_PATH = "/etc/fonts";
    
    # Cursor variables
    XCURSOR_SIZE = "24";
    
    # XDG specifications
    XDG_CONFIG_HOME = "$HOME/.config";
    XDG_CACHE_HOME = "$HOME/.cache";
    XDG_DATA_HOME = "$HOME/.local/share";
    XDG_STATE_HOME = "$HOME/.local/state";
    
    # Editor
    EDITOR = "emacs-dev";
    VISUAL = "emacs-dev";
  };
  
  # Shell configuration
  programs.bash = {
    enable = true;
    profileExtra = ''
      # Add local bins to PATH
      export PATH="$HOME/.local/bin:$PATH"
    '';
    initExtra = ''
      # Load direnv for project environments
      eval "$(direnv hook bash)"
      
      # Aliases for power management
      alias battery-status="cat /sys/class/power_supply/BAT*/capacity"
      alias power-save="gpu-switch integrated && sudo auto-cpufreq --force=powersave"
      alias performance="gpu-switch hybrid && sudo auto-cpufreq --force=performance"
      
      # Docker aliases
      alias dps="docker ps"
      alias dcu="docker-compose up -d"
      alias dcd="docker-compose down"
      alias dlogs="docker logs -f"
    '';
  };

  # Git configuration
  programs.git = {
    enable = true;
    userName = "b7r6";
    userEmail = "b7r6@b7r6.net";
    
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      
      # Improve performance
      core.preloadIndex = true;
      core.fsmonitor = true;
      
      # Use delta for better diffs
      core.pager = "delta";
      
      # Better defaults
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
    };
  };

  # SSH configuration
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "github.com" = {
        identityFile = "~/.ssh/id_ed25519";
      };
    };
  };

  # Keep Alacritty as an alternative terminal
  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        padding = { x = 10; y = 10; };
        dynamic_padding = true;
        decorations = "none";
        startup_mode = "Windowed";
        dynamic_title = true;
      };
      
      font = {
        normal = {
          family = "Berkeley Mono SemiBold";
          style = "Regular";
        };
        bold = {
          family = "Berkeley Mono SemiBold";
          style = "Bold";
        };
        italic = {
          family = "Berkeley Mono SemiBold";
          style = "Italic";
        };
        size = 12.0;
      };
      
      # Better rendering for HiDPI display
      render_timer = false;
      draw_bold_text_with_bright_colors = true;
      
      selection = {
        save_to_clipboard = true;
      };
    };
  };

  # Direnv for per-directory environment variables
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableBashIntegration = true;
  };

  # Wayland-friendly credential manager
  services.password-store-sync.enable = true;  # Use pass instead of gnome-keyring
  
  programs.password-store = {
    enable = true;
    package = flake.inputs.nixpkgs.legacyPackages.x86_64-linux.pass;
  };
  
  # Add libsecret support without GNOME
  home.packages = with flake.inputs.nixpkgs.legacyPackages.x86_64-linux; [
    # Core utilities
    bat
    btop
    fd
    fzf
    jq
    ripgrep
    tree
    tmux
    wget
    
    # Development tools
    direnv
    gh
    git-lfs
    delta # Better git diff
    
    # Media and documents
    firefox
    mpv
    zathura
    
    # Power Management
    auto-cpufreq
    powertop
    
    # Wayland specific
    wl-clipboard
    xdg-utils
    xorg.xeyes # To test XWayland
    
    # Credential management
    libsecret    # Secure storage for credentials
    pass         # Password manager
    pinentry-qt  # PIN entry dialog
    
    # Audio control
    pavucontrol
    
    # File management
    ranger
    
    # Graphics
    imv # Image viewer for Wayland
  ];

  # Enable fonts with improved configuration
  fonts.fontconfig.enable = true;
  
  # XDG configuration for better application integration
  xdg = {
    enable = true;
    mime.enable = true;
    mimeApps.enable = true;
    userDirs.enable = true;
    
    # Default applications using the emacs-dev desktop entry
    mimeApps.defaultApplications = {
      "application/pdf" = ["org.pwmt.zathura.desktop"];
      "image/*" = ["imv.desktop"];
      "video/*" = ["mpv.desktop"];
      "text/plain" = ["emacs-dev.desktop"];
      "text/x-emacs-lisp" = ["emacs-dev.desktop"];
      "text/html" = ["firefox.desktop"];
      "x-scheme-handler/http" = ["firefox.desktop"];
      "x-scheme-handler/https" = ["firefox.desktop"];
    };
  };

  # Nixpkgs configuration
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = _: true;
  };

  # Home-manager state version - using the latest unstable version
  home.stateVersion = "25.05";
} 