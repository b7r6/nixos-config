# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // test-vm
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# VM configuration for testing desktop/portal functionality.
#
# Usage:
#   # Build and run the VM (online):
#   nix run .#nixosConfigurations.test-vm.config.system.build.vm
#
#   # Or build the VM script:
#   nix build .#nixosConfigurations.test-vm.config.system.build.vm
#   ./result/bin/run-test-vm-vm
#
# Inside the VM:
#   - Auto-login as 'test' user
#   - Run 'Hyprland' to start the desktop
#   - Test portals with: portal-test (screenshot, file picker, etc.)
#
{ pkgs, lib, ... }:

{
  # ── Machine Identity ─────────────────────────────────────────────────────────

  networking.hostName = "test-vm";
  # Platform is set in default.nix based on system

  # ── Boot ─────────────────────────────────────────────────────────────────────

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Placeholder root filesystem (QEMU overrides this)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # ── Networking ───────────────────────────────────────────────────────────────

  networking.networkmanager.enable = true;

  # ── Locale ───────────────────────────────────────────────────────────────────

  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── User Configuration ───────────────────────────────────────────────────────

  users.users.test = {
    isNormalUser = true;
    description = "Test User";
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "render"
      "audio"
    ];
    initialPassword = "test";
  };

  # Home-manager for test user - minimal config (avoid duplicating Hyprland settings)
  home-manager.users.test = { pkgs, ... }: {
    home.username = "test";
    home.homeDirectory = "/home/test";
    home.stateVersion = "25.05";

    # Minimal XDG
    xdg.enable = true;

    # Packages
    home.packages = with pkgs; [
      fastfetch
      btop
      foot
      wofi
    ];

    # Simple terminal
    programs.foot = {
      enable = true;
      settings.main.font = "monospace:size=11";
    };
  };

  # ── Wayland/Desktop Configuration ────────────────────────────────────────────

  # Enable our consolidated wayland module
  hyper-modern-nixos.wayland = {
    enable = true;
    qtTheme = "qt5ct";
    electronOzone = true;
  };

  # Hyprland window manager
  programs.hyprland.enable = true;

  # Auto-login to TTY1 for easy testing
  services.getty.autologinUser = "test";

  # ── Graphics ─────────────────────────────────────────────────────────────────

  # Mesa for virtio-gpu virgl 3D acceleration
  hardware.graphics.enable = true;

  # Virgl environment hints for VM
  environment.variables = {
    WLR_RENDERER = "gles2";
    WLR_NO_HARDWARE_CURSORS = "1";
    # Disable GPU-specific features that don't work in VM
    __GLX_VENDOR_LIBRARY_NAME = "mesa";
  };

  # ── Audio ────────────────────────────────────────────────────────────────────

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Disable PulseAudio (we use PipeWire)
  services.pulseaudio.enable = false;

  # ── SSH for Remote Testing ───────────────────────────────────────────────────

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # Disable conflicting SSH agents (we use the standard one from common)
  services.gnome.gnome-keyring.enable = lib.mkForce false;

  # ── Test Tools ───────────────────────────────────────────────────────────────

  environment.systemPackages = with pkgs; [
    # Portal testing
    xdg-utils
    xdg-desktop-portal

    # Screenshot tools (to test portal)
    grim
    slurp
    grimblast

    # File picker test (GTK app that uses portal)
    zenity
    gnome-text-editor

    # Screen recording (to test screencast portal)
    wf-recorder
    obs-studio

    # Qt apps (to test Qt theming)
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    kdePackages.dolphin
    kdePackages.konsole

    # Terminal
    foot
    kitty

    # Basic utilities
    neovim
    btop
    fastfetch

    # Portal debugging (busctl is in systemd)

    # Test script
    (writeShellScriptBin "portal-test" ''
      #!/usr/bin/env bash
      set -e

      echo "=== XDG Portal Test Suite ==="
      echo ""

      echo "1. Checking portal services..."
      systemctl --user status xdg-desktop-portal.service --no-pager || true
      systemctl --user status xdg-desktop-portal-hyprland.service --no-pager || true
      systemctl --user status xdg-desktop-portal-gtk.service --no-pager || true
      echo ""

      echo "2. Checking portal config..."
      cat /etc/xdg-desktop-portal/portals.conf 2>/dev/null || echo "No portals.conf found"
      echo ""

      echo "3. Testing Screenshot portal..."
      echo "   Taking screenshot in 2 seconds..."
      sleep 2
      grimblast save screen /tmp/screenshot-test.png && echo "   ✓ Screenshot saved to /tmp/screenshot-test.png" || echo "   ✗ Screenshot failed"
      echo ""

      echo "4. Testing File Chooser portal..."
      echo "   Opening file dialog (close it to continue)..."
      zenity --file-selection --title="Portal Test: Select a file" 2>/dev/null || echo "   Dialog closed/cancelled"
      echo ""

      echo "5. Checking environment variables..."
      echo "   XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP"
      echo "   XDG_SESSION_TYPE=$XDG_SESSION_TYPE"
      echo "   QT_QPA_PLATFORM=$QT_QPA_PLATFORM"
      echo "   QT_QPA_PLATFORMTHEME=$QT_QPA_PLATFORMTHEME"
      echo "   GDK_BACKEND=$GDK_BACKEND"
      echo ""

      echo "6. D-Bus portal interfaces..."
      busctl --user list | grep -E "portal|Portal" || echo "   No portal services found on D-Bus"
      echo ""

      echo "=== Test Complete ==="
    '')

    # Offline test script
    (writeShellScriptBin "offline-test" ''
      #!/usr/bin/env bash
      set -e

      echo "=== Offline Functionality Test ==="
      echo ""

      echo "1. Checking network status..."
      ip addr show | grep -E "inet |state" || true
      echo ""

      echo "2. Testing local apps..."
      echo "   Starting foot terminal..."
      foot --title "Offline Test" -e bash -c 'echo "Terminal works!"; sleep 2' &
      sleep 3
      echo ""

      echo "3. Testing file operations..."
      mkdir -p /tmp/offline-test
      echo "test content" > /tmp/offline-test/file.txt
      cat /tmp/offline-test/file.txt
      echo "   ✓ File operations work"
      echo ""

      echo "4. Testing Hyprland IPC..."
      hyprctl version || echo "   ✗ hyprctl failed"
      hyprctl monitors || echo "   ✗ monitor query failed"
      echo ""

      echo "5. Testing audio (PipeWire)..."
      wpctl status || echo "   ✗ WirePlumber not running"
      echo ""

      echo "=== Offline Test Complete ==="
    '')
  ];

  # ── VM-specific Settings ─────────────────────────────────────────────────────

  virtualisation.vmVariant = {
    virtualisation = {
      # Resources
      memorySize = 8192; # 8GB RAM
      cores = 4;
      diskSize = 8192; # 8GB disk

      # Graphics
      graphics = true;

      # SSH port forwarding: host:2222 -> guest:22
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
      ];

      # QEMU options
      qemu.options = lib.mkAfter [
        # GTK display with OpenGL for virgl (hardware-accelerated 3D)
        "-display gtk,gl=on"
        # Alternative: SDL display
        # "-display sdl,gl=on"
        # Alternative: Headless with VNC
        # "-vnc :0"
      ];
    };

    # Simpler Hyprland config for VM
    environment.etc."hypr/hyprland-vm.conf".text = ''
      # Minimal Hyprland config for VM testing

      monitor=,preferred,auto,1

      exec-once = foot
      exec-once = mako

      input {
        kb_layout = us
        follow_mouse = 1
      }

      general {
        gaps_in = 5
        gaps_out = 10
        border_size = 2
        col.active_border = rgba(33ccffee)
        col.inactive_border = rgba(595959aa)
        layout = dwindle
      }

      decoration {
        rounding = 5
      }

      # Basic keybindings
      $mod = SUPER

      bind = $mod, Return, exec, foot
      bind = $mod, Q, killactive
      bind = $mod, M, exit
      bind = $mod, D, exec, wofi --show drun
      bind = $mod, P, exec, grimblast copy area

      # Window management
      bind = $mod, h, movefocus, l
      bind = $mod, l, movefocus, r
      bind = $mod, k, movefocus, u
      bind = $mod, j, movefocus, d

      # Workspaces
      bind = $mod, 1, workspace, 1
      bind = $mod, 2, workspace, 2
      bind = $mod, 3, workspace, 3
      bind = $mod SHIFT, 1, movetoworkspace, 1
      bind = $mod SHIFT, 2, movetoworkspace, 2
      bind = $mod SHIFT, 3, movetoworkspace, 3
    '';
  };

  # ── State Version ────────────────────────────────────────────────────────────

  system.stateVersion = "25.05";
}
