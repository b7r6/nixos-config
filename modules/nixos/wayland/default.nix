# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                      // hyper-modern-nixos // nixos // wayland
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Consolidated Wayland + XDG Portal configuration for Hyprland
#
# Key design decisions:
#   - Use xdg-desktop-portal-hyprland (native), not xdg-desktop-portal-wlr
#   - Route Screenshot/ScreenCast/Inhibit to Hyprland portal
#   - Use GTK portal as fallback for file pickers, etc.
#   - Qt apps follow GTK theme via qt5ct/qt6ct
#   - Electron apps use native Wayland (NIXOS_OZONE_WL)
#
{
  pkgs,
  lib,
  config,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    mkAliasOptionModule
    types
    ;
  cfg = config.hyper-modern-nixos.wayland;
in
{
  imports = [
    # Backward compatibility: hyper-wayland -> wayland
    (mkAliasOptionModule [ "hyper-modern-nixos" "hyper-wayland" ] [ "hyper-modern-nixos" "wayland" ])
  ];

  options.hyper-modern-nixos.wayland = {
    enable = mkEnableOption "Wayland desktop with Hyprland portal support";

    qtTheme = mkOption {
      type = types.enum [
        "gtk2"
        "qt5ct"
        "qt6ct"
        "kvantum"
        "gnome"
      ];
      default = "qt5ct";
      description = ''
        Qt theming backend:
          gtk2    - Use GTK2 theme (simple, requires gtk2 theme installed)
          qt5ct   - Use qt5ct for Qt5/Qt6 theming (recommended)
          qt6ct   - Use qt6ct for Qt6 theming
          kvantum - Use Kvantum SVG theme engine
          gnome   - Use GNOME/Adwaita style
      '';
    };

    electronOzone = mkOption {
      type = types.bool;
      default = true;
      description = "Enable native Wayland for Electron apps";
    };
  };

  config = mkIf cfg.enable {

    # ── Core Wayland packages ──────────────────────────────────────────────────

    environment.systemPackages = with pkgs; [
      # Core utilities
      dbus
      dconf
      xdg-utils
      xdg-user-dirs
      glib
      wl-clipboard
      wl-clip-persist # Clipboard persistence after app closes
      cliphist # Clipboard history for wofi/rofi

      # Qt Wayland support
      qt6.qtwayland
      qt5.qtwayland # was libsForQt5.qt5.qtwayland; the nested .qt5 alias was removed
      kdePackages.qtwayland

      # Qt theming tools
      libsForQt5.qt5ct
      qt6Packages.qt6ct
      libsForQt5.qtstyleplugins # For gtk2 style

      # KDE/Plasma protocols (for portals and some apps)
      kdePackages.plasma-wayland-protocols

      # GTK support
      gtk3
      gtk4
      gsettings-desktop-schemas

      # Icon themes (ensure consistent icons)
      hicolor-icon-theme
      adwaita-icon-theme
      kdePackages.breeze-icons

      # Portal debugging
      xdg-desktop-portal

      # Portal test suite (backported from new-suzuki) — exercises the portal
      # stack end to end: service state, routing config, Screenshot and
      # FileChooser over D-Bus. Run after any compositor/portal change.
      (pkgs.writeShellScriptBin "portal-test" ''
        echo "=== XDG Portal Test Suite ==="
        echo ""

        echo "1. Checking portal services..."
        systemctl --user status xdg-desktop-portal.service --no-pager || true
        systemctl --user status xdg-desktop-portal-hyprland.service --no-pager || true
        systemctl --user status xdg-desktop-portal-gtk.service --no-pager || true
        echo ""

        echo "2. Checking portal config..."
        # n.b. NixOS renders xdg.portal.config here — not /etc/xdg-desktop-portal
        # (the upstream default the new-suzuki branch checked, wrongly, on NixOS)
        cat /etc/xdg/xdg-desktop-portal/*.conf 2>/dev/null || echo "No portal config found"
        echo ""

        echo "3. Testing Screenshot portal..."
        echo "   Taking screenshot in 2 seconds..."
        sleep 2
        ${pkgs.grimblast}/bin/grimblast save screen /tmp/portal-test-screenshot.png \
          && echo "   ok: screenshot saved to /tmp/portal-test-screenshot.png" \
          || echo "   FAIL: screenshot failed"
        echo ""

        echo "4. Testing File Chooser portal..."
        echo "   Opening file dialog (close it to continue)..."
        ${pkgs.zenity}/bin/zenity --file-selection --title="Portal Test: Select a file" 2>/dev/null \
          || echo "   dialog closed/cancelled"
        echo ""

        echo "5. Checking environment variables..."
        echo "   XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP"
        echo "   XDG_SESSION_TYPE=$XDG_SESSION_TYPE"
        echo "   QT_QPA_PLATFORM=$QT_QPA_PLATFORM"
        echo "   QT_QPA_PLATFORMTHEME=$QT_QPA_PLATFORMTHEME"
        echo ""

        echo "6. D-Bus portal interfaces..."
        busctl --user list | grep -iE "portal" || echo "   no portal services found on D-Bus"
        echo ""

        echo "=== Test Complete ==="
      '')
    ];

    # ── Hyprland: compositor + portal from the SAME source ──────────────────────
    # programs.hyprland installs the compositor system-wide (session file for
    # greetd, PATH, XDG_CURRENT_DESKTOP) and injects its portalPackage into
    # xdg.portal.extraPortals. package/portalPackage stay at their defaults
    # deliberately: both resolve from this one nixpkgs, so compositor and
    # portal can never skew — skew between the two is the classic cause of
    # broken screenshot/screencast. home-manager's hyprland module resolves
    # the same attr, so the session runs this same derivation.
    programs.hyprland.enable = true;

    # ── XDG Portal Configuration ───────────────────────────────────────────────

    #
    # Best practices for Hyprland:
    #   - xdg-desktop-portal-hyprland comes via programs.hyprland.portalPackage
    #     (same-source with the compositor, see above) — NOT listed here
    #   - Use xdg-desktop-portal-gtk for file dialogs, app chooser, etc.
    #   - Do NOT use xdg-desktop-portal-wlr (generic wlroots, less features)
    #   - Do NOT enable wlr.enable (conflicts with hyprland portal)
    #

    xdg.portal = {
      enable = true;

      # GTK fallback portal (hyprland portal injected by programs.hyprland)
      extraPortals = with pkgs; [ xdg-desktop-portal-gtk ];

      # Explicit portal routing
      config = {
        # Common defaults (used when no desktop-specific config matches)
        common = {
          # GTK portal handles most things well
          default = [ "gtk" ];

          # File chooser - GTK provides nice native dialogs
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];

          # App chooser - GTK
          "org.freedesktop.impl.portal.AppChooser" = [ "gtk" ];
        };

        # Hyprland-specific overrides
        hyprland = {
          # Default to trying Hyprland first, then GTK
          default = [
            "hyprland"
            "gtk"
          ];

          # Screen capture MUST use Hyprland portal
          "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
          "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];

          # Session inhibit (prevent sleep during video, etc.)
          "org.freedesktop.impl.portal.Inhibit" = [ "hyprland" ];

          # Global shortcuts
          "org.freedesktop.impl.portal.GlobalShortcuts" = [ "hyprland" ];

          # File chooser still uses GTK (better UI)
          "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
          "org.freedesktop.impl.portal.AppChooser" = [ "gtk" ];

          # Secret storage
          "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
        };
      };

      # Use portal for xdg-open (consistent behavior)
      xdgOpenUsePortal = true;
    };

    # ── Environment Variables ──────────────────────────────────────────────────

    environment.sessionVariables = {
      # ── Wayland enforcement ──
      XDG_CURRENT_DESKTOP = "Hyprland";
      XDG_SESSION_TYPE = "wayland";
      XDG_SESSION_DESKTOP = "Hyprland";

      # ── Electron/Chromium ──
      NIXOS_OZONE_WL = if cfg.electronOzone then "1" else "0";
      ELECTRON_OZONE_PLATFORM_HINT = "auto"; # Let Electron auto-detect

      # ── Mozilla ──
      MOZ_ENABLE_WAYLAND = "1";
      MOZ_DBUS_REMOTE = "1"; # Better Firefox integration

      # ── NVIDIA VA-API ──
      NVD_BACKEND = "direct";
      LIBVA_DRIVER_NAME = "nvidia";

      # ── Aquamarine (Hyprland backend) ──
      AQ_NO_ATOMIC = "1"; # NVIDIA atomic modesetting is buggy

      # ── Java ──
      _JAVA_AWT_WM_NONREPARENTING = "1";
      AWT_TOOLKIT = "MToolkit"; # Better Java GUI support

      # ── Qt ──
      QT_QPA_PLATFORM = "wayland;xcb"; # Wayland preferred, X11 fallback
      QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
      QT_AUTO_SCREEN_SCALE_FACTOR = "1";
      QT_QPA_PLATFORMTHEME = cfg.qtTheme;

      # ── GTK ──
      GDK_BACKEND = "wayland,x11"; # Wayland preferred, X11 fallback

      # ── SDL ──
      SDL_VIDEODRIVER = "wayland,x11"; # Wayland preferred, X11 fallback

      # ── Clutter ──
      CLUTTER_BACKEND = "wayland";

      # ── Wine ──
      # WINEFSYNC = "1";  # Uncomment if using wine
    };

    # ── D-Bus ──────────────────────────────────────────────────────────────────

    services.dbus = {
      enable = true;
      # Use broker implementation (faster, more reliable)
      implementation = "broker";
    };

    # ── GNOME services for portal integration ──────────────────────────────────

    # GSettings/dconf (required for GTK apps to read settings)
    programs.dconf.enable = true;

    # GNOME keyring for the secrets portal ONLY — its ssh-agent role is
    # deliberately dead. The fleet uses passphrase-less keys (agenix requires
    # them), so gcr-ssh-agent's whole value — GUI passphrase prompts,
    # keyring-unlocked keys — buys nothing here, and its socket shadowing
    # SSH_AUTH_SOCK repeatedly broke agent forwarding (dead socket on
    # headless hosts clobbering the live forwarded one). The standard
    # ssh-agent from base.nix (programs.ssh.startAgent, default true) serves
    # everything, desktop and headless alike.
    services.gnome.gnome-keyring.enable = true;
    services.gnome.gcr-ssh-agent.enable = false;
    security.pam.services.login.enableGnomeKeyring = true;

    # ── Polkit (required for many desktop operations) ──────────────────────────

    security.polkit.enable = true;

    # GNOME polkit agent is more reliable than others
    systemd.user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };

    # ── XDG directories ────────────────────────────────────────────────────────

    xdg.mime.enable = true;

    # ── Disable X11 ────────────────────────────────────────────────────────────

    services.xserver.enable = lib.mkDefault false;

    # ── Fonts (ensure consistent rendering) ────────────────────────────────────

    fonts.fontconfig = {
      enable = true;
      antialias = true;

      hinting = {
        enable = true;
        autohint = false;
        style = "slight";
      };

      subpixel = {
        # LG WOLED panels use WRGB stripe — subpixel rendering works correctly
        rgba = "rgb";
        lcdfilter = "default";
      };
    };
  };
}
