# Minimal VM with Hyprland
{ config, pkgs, ... }:

{
  imports = [
    <nixpkgs/nixos/modules/virtualisation/qemu-vm.nix>
  ];
  
  # VM settings
  virtualisation = {
    memorySize = 4096;
    cores = 4;
    graphics = true;
    resolution = { x = 1920; y = 1080; };
    # Virtio GPU with GL acceleration
    useGLXGuestInterface = true;
    qemu.options = [
      # Force use of software rendering
      "-vga virtio"
      "-device virtio-gpu-pci"
      # Increase video memory
      "-global virtio-gpu-pci.max_outputs=1"
    ];
  };
  
  # Basic system configuration
  environment.systemPackages = with pkgs; [
    hyprland
    wezterm
    firefox
    kitty     # Lightweight alternative terminal
    waybar    # Status bar for Hyprland
    wofi      # Application launcher
    xterm     # Fallback terminal
    neofetch  # System info display
    pciutils  # For lspci
    curl
    wget
    git
    sway      # Alternative Wayland compositor as fallback
    swaylock
    swayidle
  ];
  
  # Enable Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };
  
  # Basic Wayland environment
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  
  # Required for Hyprland
  hardware.opengl = {
    enable = true;
    driSupport = true;
  };
  
  # Environment variables to fix Hyprland VM issues
  environment.sessionVariables = {
    # Fix for cursor in VM
    WLR_NO_HARDWARE_CURSORS = "1";
    # Fix for various rendering issues in VM
    LIBGL_ALWAYS_SOFTWARE = "1";
    # Black screen fix
    WLR_RENDERER = "pixman";
    WLR_RENDERER_ALLOW_SOFTWARE = "1";
  };
  
  # Add user
  users.users.b7r6 = {
    isNormalUser = true;
    description = "Test User";
    extraGroups = [ "networkmanager" "wheel" "video" "audio" ];
    initialPassword = "password";
    packages = with pkgs; [
      firefox
    ];
    # Basic Hyprland config for testing
    home.file.".config/hypr/hyprland.conf".text = ''
      # VM-specific environment variables
      env = WLR_NO_HARDWARE_CURSORS,1
      env = LIBGL_ALWAYS_SOFTWARE,1
      env = WLR_RENDERER,pixman
      env = WLR_RENDERER_ALLOW_SOFTWARE,1
      
      # Default monitor
      monitor=,preferred,auto,1

      # Basic key bindings
      bind = SUPER, Return, exec, kitty
      bind = SUPER SHIFT, Return, exec, wezterm
      bind = SUPER, Q, killactive, 
      bind = SUPER SHIFT, E, exit, 
      bind = SUPER, D, exec, wofi --show drun
      bind = SUPER, F, fullscreen
      
      # Appearance - minimal for VM
      decoration {
        rounding = 0
        blur = false
        drop_shadow = false
      }
      
      # Animations - disabled for VM
      animations {
        enabled = false
      }
      
      # General settings
      general {
        gaps_in = 0
        gaps_out = 0
        border_size = 2
        col.active_border = rgba(33ccffee)
        layout = dwindle
      }
      
      # Start waybar
      exec-once = waybar
    '';
    
    # Add fallback Sway configuration
    home.file.".config/sway/config".text = ''
      # Default sway config
      output * bg #000000 solid_color
      
      # Basic key bindings
      set $mod Mod4
      bindsym $mod+Return exec kitty
      bindsym $mod+q kill
      bindsym $mod+Shift+e exit
      bindsym $mod+d exec wofi --show drun
      
      # Start waybar
      exec waybar
    '';
  };
  
  # Auto-login and start Hyprland
  services.xserver = {
    enable = true;
    displayManager = {
      autoLogin = {
        enable = true;
        user = "b7r6";
      };
      # Try sway first if Hyprland fails
      defaultSession = "hyprland";
      lightdm = {
        enable = true;
        greeter.enable = true;
      };
    };
  };
  
  # Configure Waybar
  environment.etc."xdg/waybar/config".text = ''
    {
      "layer": "top",
      "position": "top",
      "height": 30,
      "modules-left": ["hyprland/workspaces"],
      "modules-center": ["hyprland/window"],
      "modules-right": ["cpu", "memory", "clock", "tray"],
      "clock": {
        "format": "{:%H:%M}"
      },
      "cpu": {
        "format": "CPU: {usage}%"
      },
      "memory": {
        "format": "RAM: {}%"
      },
      "hyprland/window": {
        "max-length": 80
      }
    }
  '';
  
  # For testing, make sudo passwordless
  security.sudo.wheelNeedsPassword = false;
  
  # Network and firewall
  networking = {
    firewall.enable = false;
    useDHCP = true;
  };
  
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  
  # Set environment for autologin
  systemd.user.targets.hyprland-session = {
    description = "Hyprland compositor session";
    bindsTarget = ["graphical-session.target"];
    wants = ["graphical-session-pre.target"];
    after = ["graphical-session-pre.target"];
    wantedBy = ["graphical-session.target"];
  };
  
  # Create a script to try Hyprland, fall back to Sway if it fails
  environment.etc."hyprland-wrapper.sh" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      export WLR_NO_HARDWARE_CURSORS=1
      export LIBGL_ALWAYS_SOFTWARE=1
      export WLR_RENDERER=pixman
      export WLR_RENDERER_ALLOW_SOFTWARE=1
      
      # Try to run Hyprland
      Hyprland || sway
    '';
  };
  
  # Add script to start hyprland automatically
  systemd.user.services.hyprland = {
    description = "Hyprland - Wayland Compositor";
    documentation = ["man:Hyprland(1)"];
    bindsTo = ["graphical-session.target"];
    wants = ["graphical-session-pre.target"];
    after = ["graphical-session-pre.target"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "/etc/hyprland-wrapper.sh";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
  
  # System version
  system.stateVersion = "23.11";
} 