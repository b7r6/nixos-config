# Main system configuration for ASUS ProArt P16
{ config, pkgs, ... }:

{
  imports = [
    # Include hardware configuration
    ./hardware-configuration.nix
    # Include Docker configuration
    ../modules/system/docker.nix
    # Include rEFInd configuration - commented out until verified
    # ../modules/system/refind.nix
  ];

  # Enable Docker with custom configuration
  services.docker-proart = {
    enable = true;
    enableNvidia = true;  # Enable NVIDIA GPU support for Docker
    enableAMD = true;     # Enable AMD GPU support for Docker
    installCompose = true; # Install Docker Compose
  };

  # rEFInd configuration - commented out until verified with boot ISO
  # boot.refind-proart = {
  #   enable = true;
  #   useGraphics = true;
  #   resolution = "3840 2160"; # 4K for ProArt display
  #   themeName = "ursamajor";
  # };

  # Bootloader configuration compatible with greetd
  boot = {
    # Use systemd-boot (compatible with greetd)
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
        consoleMode = "max";
        # Enable editor for boot parameters
        editor = true;
      };
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
      timeout = 5;  # Boot menu timeout in seconds
    };
    
    # Improve boot time with better parallelization
    initrd.verbose = false;
    consoleLogLevel = 0;
    kernelParams = [ 
      "quiet" 
      "splash" 
      "rd.systemd.show_status=false" 
      "rd.udev.log_level=3" 
      "udev.log_priority=3"
      # Enable proper lid switch handling
      "button.lid_init_state=open"
    ];
    
    # Add Plymouth for a prettier boot
    plymouth = {
      enable = true;
      theme = "breeze";
    };
  };

  # System identification
  networking.hostName = "proart"; # Define your hostname
  
  # Use NetworkManager with better power management
  networking.networkmanager = {
    enable = true;
    wifi.powersave = true;
  };

  # Power management optimizations
  powerManagement = {
    enable = true;
    cpuFreqGovernor = "ondemand"; # Changes to "powersave" on battery with TLP
    powertop.enable = true;
  };
  
  # Enable thermald for better thermal management
  services.thermald.enable = true;
  
  # Enable auto-cpufreq for improved power management
  services.auto-cpufreq = {
    enable = true;
    settings = {
      battery = {
        governor = "powersave";
        turbo = "never";
      };
      charger = {
        governor = "performance";
        turbo = "auto";
      };
    };
  };

  # Configure login manager - use greetd with tuigreet
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };
  };
  
  # Configure tuigreet theme
  environment.etc."greetd/environments".text = ''
    Hyprland
    bash
  '';

  # Configure ACPI events for proper lid handling
  services.acpid = {
    enable = true;
    handlers = {
      lid-close = {
        event = "button/lid.*";
        action = ''
          # Allow monitor-handler script to manage lid events
          export SWAYSOCK="/run/user/$(id -u b7r6)/sway-ipc.$(id -u b7r6).$(pgrep -x sway -u b7r6).sock"
          export HYPRLAND_INSTANCE_SIGNATURE="$(ls -1 /tmp/hypr/ | head -1)"
          if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
            runuser -l b7r6 -c "monitor-handler handle-lid"
          fi
        '';
      };
    };
    lidEventCommands = ''
      # Handled by the lid-close handler for more flexibility
    '';
  };

  # Networking services
  services = {
    # Tailscale for secure networking
    tailscale.enable = true;
    
    # Remote access
    openssh.enable = true;
    
    # Audio
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };
    
    # Printing
    printing.enable = true;
  };

  # Secure access
  programs.ssh.startAgent = true;
  security.rtkit.enable = true;
  
  # Enable Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ ];
  };
  
  # Mullvad VPN with kill switch for better security
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
    enableExcludeHosts = true; # For split tunneling
  };

  # Enable Hyprland at the system level
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Nix configuration
  nix = {
    # Use the latest stable Nix package
    package = pkgs.nixVersions.latest;
    
    extraOptions = ''
      experimental-features = nix-command flakes pipe-operators
      extra-substituters = https://cache.nixos.org/ https://cache.garnix.io/
      extra-trusted-public-keys = cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=
      connect-timeout = 5
    '';
    
    settings = {
      auto-optimise-store = true;
      trusted-users = [ "root" "@wheel" ];
      
      # Cachix configuration with additional caches
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://hyprland.cachix.org"
        "https://cache.garnix.io"       # Additional cache for faster builds
        "https://numtide.cachix.org"    # Additional cache
      ];
      
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE="
      ];
    };
    
    # Garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    
    # Additional optimization for the Nix store
    optimise.automatic = true;
    optimise.dates = [ "weekly" ];
  };

  # User setup
  users.users.b7r6 = {
    isNormalUser = true;
    description = "b7r6";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" "docker" ];
    shell = pkgs.bash;
    # Pre-hashed password (SHA-512)
    hashedPassword = "$6$4/p3K74/8A.MZ8T1$fH9tiQmg04vRhfOdrPDJ8LSJrXm4kLLy4iGQoo2LgS4pHU.nrA6rySQHBY5R6ApLQXQ7ooH.dcI32tfeu1lLS0";
  };
  
  security.sudo.wheelNeedsPassword = false;

  # System packages
  environment.systemPackages = with pkgs; [
    # Basic utilities
    wezterm              # Primary terminal
    alacritty            # Alternative terminal
    cacert
    curl
    git
    home-manager
    neovim
    ripgrep
    wget
    
    # Development tools
    gnumake
    gcc
    
    # System tools
    bottom
    htop
    pciutils
    usbutils
    
    # Monitor handling dependencies
    jq
    inotify-tools
    socat
    
    # Network tools
    tailscale
    mullvad-vpn
    
    # Special tools for ASUS ProArt
    supergfxctl         # GPU control for hybrid graphics
    acpi                # ACPI utilities
    acpid               # ACPI daemon
    brightnessctl       # Brightness control
    
    # Font packages - Make Berkeley Mono available system-wide
    (stdenv.mkDerivation {
      name = "berkeley-mono-system";
      src = builtins.path { 
        path = ../berekelyMono.zip; 
        name = "berkeley-mono-zip";
      };
      nativeBuildInputs = [ unzip ];
      unpackPhase = "unzip $src";
      installPhase = ''
        mkdir -p $out/share/fonts/opentype
        cp *.otf $out/share/fonts/opentype/
      '';
    })
    
    # GPU driver support packages
    mesa
    libva
    vaapiVdpau
    
    # Custom GPU switching tool
    (writeShellScriptBin "gpu-switch" ''
      #!/usr/bin/env bash
      
      function show_help {
        echo "GPU Switching Utility for ASUS ProArt P16"
        echo "Usage: gpu-switch [option]"
        echo "Options:"
        echo "  integrated   - Switch to integrated graphics (AMD Radeon 890M) for better battery"
        echo "  hybrid       - Use hybrid mode (AMD + NVIDIA on demand) for balanced usage"
        echo "  dedicated    - Use dedicated graphics (NVIDIA RTX 4060) for maximum performance"
        echo "  status       - Show current graphics mode and status"
        echo "  help         - Show this help message"
      }
      
      function switch_graphics {
        echo "Switching to $1 mode..."
        supergfxctl -m $1
        echo "Please log out and log back in for changes to take effect."
      }
      
      function show_status {
        echo "Current Graphics Mode:"
        supergfxctl -g
        echo ""
        echo "GPU Status:"
        echo "AMD Radeon 890M:"
        if command -v radeontop &> /dev/null; then
          radeontop -d- -l1
        else
          echo "radeontop not installed"
        fi
        echo ""
        echo "NVIDIA RTX 4060:"
        if command -v nvidia-smi &> /dev/null; then
          nvidia-smi
        else
          echo "nvidia-smi not installed"
        fi
        echo ""
        echo "Power Consumption:"
        if command -v powertop &> /dev/null; then
          powertop --time=5 --csv=/tmp/powertop.csv
          grep -A 3 "Power est" /tmp/powertop.csv | tail -n 3
          rm /tmp/powertop.csv
        else
          echo "powertop not installed"
        fi
      }
      
      case "$1" in
        "integrated")
          switch_graphics "integrated"
          ;;
        "hybrid")
          switch_graphics "hybrid"
          ;;
        "dedicated")
          switch_graphics "dedicated"
          ;;
        "status")
          show_status
          ;;
        "help" | *)
          show_help
          ;;
      esac
    '')
  ];

  # System-wide font configuration
  fonts = {
    enableDefaultPackages = true;
    fontconfig = {
      defaultFonts = {
        monospace = [ "Berkeley Mono SemiBold" ];
        sansSerif = [ "Berkeley Mono SemiBold" ];
        serif = [ "Berkeley Mono SemiBold" ];
      };
    };
    packages = with pkgs; [
      noto-fonts
      noto-fonts-emoji
      (stdenv.mkDerivation {
        name = "berkeley-mono-fonts";
        src = builtins.path { 
          path = ../berekelyMono.zip; 
          name = "berkeley-mono-zip";
        };
        nativeBuildInputs = [ unzip ];
        unpackPhase = "unzip $src";
        installPhase = ''
          mkdir -p $out/share/fonts/opentype
          cp *.otf $out/share/fonts/opentype/
        '';
      })
    ];
  };

  # Wayland support
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  
  # Added session variables for proper display initialization
  environment.sessionVariables = {
    # Force applications to use AMD GPU by default
    DRI_PRIME = "1";
    
    # Configure card ordering for Wayland
    WLR_DRM_DEVICES = "/dev/dri/card0:/dev/dri/card1";
    
    # Hardware acceleration settings
    LIBVA_DRIVER_NAME = "radeonsi";
    MOZ_DISABLE_RDD_SANDBOX = "1";
    
    # Fix for screen tearing and compositor issues
    __GL_SYNC_TO_VBLANK = "0";
  };
  
  # GPU and display driver configuration for ProArt P16
  services.xserver.videoDrivers = [ "amdgpu" "nvidia" ];
  
  # NVIDIA driver configuration
  hardware.nvidia = {
    # Modesetting for Wayland support
    modesetting.enable = true;
    
    # Power management
    powerManagement.enable = true;
    
    # Open driver
    open = false;
    
    # Force full composition pipeline for better performance
    forceFullCompositionPipeline = true;
    
    # Settings for hybrid graphics - using AMD as primary
    prime = {
      offload.enable = true;
      # Correct PCI bus IDs for this hardware
      amdgpuBusId = "PCI:6:0:0"; # AMD Radeon 890M
      nvidiaBusId = "PCI:1:0:0"; # NVIDIA RTX 4060
    };
  };
  
  # AMD GPU configuration
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      rocm-opencl-icd
      rocm-opencl-runtime
      amdvlk
      vaapiVdpau
      libvdpau-va-gl
    ];
  };
  
  # Locale and time
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  
  # Browser
  programs.firefox.enable = true;
  
  # System state version - use the latest unstable channel
  system.stateVersion = "25.05";
} 