# Xremap configuration for Emacs-style keybindings
{ config, lib, pkgs, ... }:

let
  # Define an YAML config for xremap with Emacs keybindings
  xremapConfig = pkgs.writeText "xremap-config.yml" ''
keymap:
  - name: Emacs-like Keybindings
    application:
      not: [Emacs, emacs]
    remap:
      # Cursor movement
      C-b: { with_mark: left }
      C-f: { with_mark: right }
      C-p: { with_mark: up }
      C-n: { with_mark: down }
      
      # Forward/Backward word
      M-b: { with_mark: C-left }
      M-f: { with_mark: C-right }
      
      # Beginning/End of line
      C-a: { with_mark: home }
      C-e: { with_mark: end }
      
      # Page up/down
      M-v: { with_mark: pageup }
      C-v: { with_mark: pagedown }
      
      # Beginning/End of file
      M-Shift-comma: { with_mark: C-home }
      M-Shift-dot: { with_mark: C-end }
      
      # Newline
      C-m: enter
      C-j: enter
      C-o: [enter, left]
      
      # Copy/Cut/Paste
      C-w: [C-x, { set_mark: false }]
      M-w: [C-c, { set_mark: false }]
      C-y: [C-v, { set_mark: false }]
      
      # Delete
      C-d: [delete, { set_mark: false }]
      M-d: [C-delete, { set_mark: false }]
      
      # Kill line
      C-k: [Shift-end, C-x, { set_mark: false }]
      
      # Kill word backward
      C-backspace: [C-backspace, { set_mark: false }]
      M-backspace: [C-backspace, { set_mark: false }]
      
      # Undo
      C-slash: [C-z, { set_mark: false }]
      C-underscore: [C-z, { set_mark: false }]
      
      # Mark
      C-space: { set_mark: true }
      
      # Search
      C-s: C-f
      C-r: Shift-F3
      
      # Cancel
      C-g: [esc, { set_mark: false }]
      
      # C-x prefix commands
      C-x:
        remap:
          # C-x h (select all)
          h: [C-home, C-a, { set_mark: true }]
          # C-x C-f (open file)
          C-f: C-o
          # C-x C-s (save)
          C-s: C-s
          # C-x k (kill/close)
          k: C-w
          # C-x C-c (exit)
          C-c: C-q
          # C-x u (undo)
          u: [C-z, { set_mark: false }]
          # C-x C-k (delete region)
          C-k: [C-x, { set_mark: false }]
  '';
  
  # Create the xremap service script
  startXremap = pkgs.writeShellScriptBin "start-xremap" ''
    #!/usr/bin/env bash
    
    # Check if xremap is already running
    if pgrep -x "xremap" > /dev/null; then
      echo "xremap is already running. Restarting..."
      pkill -x "xremap"
    fi
    
    # Start xremap with appropriate device permissions
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
      # For Wayland
      exec ${pkgs.xremap}/bin/xremap --watch-device --device "name-not-contains=UNIW0001|3" ${xremapConfig} &
    else
      # For X11
      exec ${pkgs.xremap}/bin/xremap --watch-device ${xremapConfig} &
    fi
  '';
in
{
  options.services.xremap = {
    enable = lib.mkEnableOption "Enable xremap for Emacs keybindings";
  };

  config = lib.mkIf config.services.xremap.enable {
    # Install xremap and our startup script
    home.packages = with pkgs; [
      xremap
      startXremap
      # Required for device detection
      inotify-tools
    ];
    
    # Autostart xremap for Wayland session
    wayland.windowManager.hyprland.settings.exec-once = [
      "${startXremap}/bin/start-xremap"
    ];
    
    # Create systemd user service for xremap
    systemd.user.services.xremap = {
      Unit = {
        Description = "xremap key remapping service";
        After = [ "graphical-session-pre.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      
      Service = {
        Type = "simple";
        ExecStart = "${startXremap}/bin/start-xremap";
        Restart = "always";
        RestartSec = 3;
      };
      
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
    
    # Create config directory for xremap
    home.file.".config/xremap/config.yml".source = xremapConfig;
  };
} 