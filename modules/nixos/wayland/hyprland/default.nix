{
  flake,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hypermodern.nixos.wayland;
  inherit (flake) inputs;

  inherit (config.lib.stylix) colors;
  base00 = lib.removePrefix "#" colors.base00; # background
  base01 = lib.removePrefix "#" colors.base01; # lighter background
  base02 = lib.removePrefix "#" colors.base02; # selection background # comments/dark
  base04 = lib.removePrefix "#" colors.base04; # dark foreground
  base05 = lib.removePrefix "#" colors.base05; # foreground # light foreground # light background
  base08 = lib.removePrefix "#" colors.base08; # red # orange
  base0A = lib.removePrefix "#" colors.base0A; # yellow
  base0B = lib.removePrefix "#" colors.base0B; # green # cyan
  base0D = lib.removePrefix "#" colors.base0D; # blue
  base0E = lib.removePrefix "#" colors.base0E; # purple # dark accent
in
{
  config = lib.mkIf (cfg.enable && cfg.hyprland.enable) {

    programs.hyprland = {
      enable = true;
      package = inputs.hyprland.packages.${pkgs.system}.hyprland;
      xwayland.enable = false;
    };

    environment.systemPackages = with pkgs; [
      inputs.hy3.outputs.packages.${pkgs.system}.hy3

      blueman
      brightnessctl
      flameshot
      grim
      grimblast
      hyprpaper
      hyprpicker
      jq
      libnotify
      mako
      nm-tray
      pamixer
      pavucontrol
      playerctl
      slurp
      swappy
      tailscale-systray
      wev
      wl-clipboard
      wlr-randr
      wofi
    ];

    # TODO[b7r6]: this probably belonds in an option and/or elsewehre...
    system.activationScripts.ensureScreenshotDirs = ''
      for user in /home/*; do
        if [ -d "$user" ]; then
          username=$(basename "$user")
          mkdir -p "$user/Screenshots"
          chown "$username:username" "$user/Screenshots"
        fi
      done
    '';

    environment.etc."hyprland/hyprland.conf".text = ''
      monitor = eDP-1,3840x2400@60.00000,0x0,2.5

      # Workspace configuration
      workspace = 1, monitor:eDP-1, default:true, persistent:true
      workspace = 2, monitor:eDP-1, persistent:true
      workspace = 3, monitor:eDP-1, persistent:true
      workspace = 4, monitor:eDP-1, persistent:true
      workspace = 5, monitor:eDP-1, persistent:true
      workspace = 6, monitor:eDP-1, persistent:true
      workspace = special:scratchpad, on-created-empty:wezterm

      exec-once = blueman-applet
      exec-once = flameshot
      exec-once = hyprpaper
      exec-once = mako
      exec-once = nm-tray
      exec-once = tailscale-systray

      general {
        border_size = 2
        gaps_in = 2
        gaps_out = 2
        layout = hy3
        resize_on_border = true
        col.active_border = rgba(${base0D}ee) rgba(${base0E}ee) 45deg
        col.inactive_border = rgba(${base02}aa)
      }

      decoration {
        rounding = 0
        blur {
          enabled = true
          size = 3
          passes = 1
          new_optimizations = true
          xray = false
          ignore_opacity = true
        }
        active_opacity = 1.0
        inactive_opacity = 0.95
        fullscreen_opacity = 1.0
      }

      animations {
        enabled = true
        bezier = easeOutQuint, 0.22, 1, 0.36, 1
        bezier = easeInQuint, 0.64, 0, 0.78, 0
        animation = windows, 1, 3, easeOutQuint
        animation = windowsOut, 1, 3, easeInQuint, popin 80%
        animation = border, 1, 3, easeOutQuint
        animation = fade, 1, 3, easeOutQuint
        animation = workspaces, 1, 3, easeOutQuint
        animation = specialWorkspace, 1, 3, easeOutQuint, slidevert
      }

      input {
        kb_layout = us
        follow_mouse = 1
        sensitivity = 0
        accel_profile = flat
        touchpad {
          natural_scroll = true
          disable_while_typing = true
          clickfinger_behavior = true
          tap-to-click = true
          drag_lock = true
        }
        kb_options = ctrl:nocaps
      }

      gestures {
        workspace_swipe = true
        workspace_swipe_fingers = 3
        workspace_swipe_distance = 300
        workspace_swipe_invert = false
        workspace_swipe_create_new = false
      }

      misc {
        force_default_wallpaper = 0
        animate_mouse_windowdragging = false
        animate_manual_resizes = false
        enable_swallow = true
        swallow_regex = ^(wezterm|ghostty|alacritty)$
        focus_on_activate = true
        disable_hyprland_logo = true
        disable_splash_rendering = true
        vfr = true
      }

      plugin:hy3 {
        tabs {
          height = 16
          padding = 0
          from_top = true
          rounding = 0
          render_text = true
          col.active = rgba(${base0D}ee)
          col.inactive = rgba(${base02}aa)
          col.text.active = rgba(${base05}ee)
          col.text.inactive = rgba(${base04}aa)
          border_width = 1
        }
        autotile {
          enable = true
          trigger_width = 800
          trigger_height = 500
          main_ratio = 0.5
        }
      }

      $mod = SUPER
      $alt = ALT

      # Core bindings
      bind = $mod, Return, exec, wezterm
      bind = $mod, Space, exec, wofi --show drun
      bind = $mod, E, exec, nemo
      bind = $mod, W, exec, firefox
      bind = $mod, BackSpace, killactive
      bind = $mod SHIFT, BackSpace, exit

      # Window states
      bind = $mod, F, fullscreen, 0
      bind = $mod SHIFT, F, fullscreen, 1
      bind = $mod, D, togglefloating
      bind = $mod, P, pin

      # Layout controls with hy3
      bind = $mod, V, hy3:makegroup, v
      bind = $mod, B, hy3:makegroup, h
      bind = $mod, T, hy3:makegroup, tab
      bind = $mod, G, hy3:changegroup, toggletab
      bind = $mod, R, hy3:changefocus, raise
      bind = $mod SHIFT, G, hy3:changegroup, opposite

      # Monitor navigation
      bind = $mod, comma, focusmonitor, -1
      bind = $mod, period, focusmonitor, +1
      bind = $mod SHIFT, comma, movecurrentworkspacetomonitor, -1
      bind = $mod SHIFT, period, movecurrentworkspacetomonitor, +1

      # Workspace switching
      bind = $mod, Tab, workspace, m+1
      bind = $mod SHIFT, Tab, workspace, m-1
      bind = $mod $alt, Tab, workspace, +1
      bind = $mod $alt SHIFT, Tab, workspace, -1

      # Direct workspace access
      bind = $mod, 1, workspace, 1
      bind = $mod, 2, workspace, 2
      bind = $mod, 3, workspace, 3
      bind = $mod, 4, workspace, 4
      bind = $mod, 5, workspace, 5
      bind = $mod, 6, workspace, 6
      bind = $mod, 7, workspace, 7
      bind = $mod, 8, workspace, 8
      bind = $mod, 9, workspace, 9
      bind = $mod, 0, workspace, 10

      # Move windows to workspaces
      bind = $mod SHIFT, 1, movetoworkspace, 1
      bind = $mod SHIFT, 2, movetoworkspace, 2
      bind = $mod SHIFT, 3, movetoworkspace, 3
      bind = $mod SHIFT, 4, movetoworkspace, 4
      bind = $mod SHIFT, 5, movetoworkspace, 5
      bind = $mod SHIFT, 6, movetoworkspace, 6
      bind = $mod SHIFT, 7, movetoworkspace, 7
      bind = $mod SHIFT, 8, movetoworkspace, 8
      bind = $mod SHIFT, 9, movetoworkspace, 9
      bind = $mod SHIFT, 0, movetoworkspace, 10

      # Window focus - vim keys
      bind = $mod, H, hy3:movefocus, l
      bind = $mod, L, hy3:movefocus, r
      bind = $mod, K, hy3:movefocus, u
      bind = $mod, J, hy3:movefocus, d

      # Move windows - vim keys
      bind = $mod SHIFT, H, hy3:movewindow, l
      bind = $mod SHIFT, L, hy3:movewindow, r
      bind = $mod SHIFT, K, hy3:movewindow, u
      bind = $mod SHIFT, J, hy3:movewindow, d

      # Resize windows
      bind = $mod $alt, H, resizeactive, -20 0
      bind = $mod $alt, L, resizeactive, 20 0
      bind = $mod $alt, K, resizeactive, 0 -20
      bind = $mod $alt, J, resizeactive, 0 20

      # Screenshots
      bind = $mod, S, exec, grimblast copy area
      bind = $mod SHIFT, S, exec, grimblast save area $HOME/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png
      bind = $mod $alt, S, exec, grimblast copy screen
      bind = $mod $alt SHIFT, S, exec, grimblast save screen $HOME/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png

      # Media controls
      bind = , XF86AudioRaiseVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ +5%
      bind = , XF86AudioLowerVolume, exec, pactl set-sink-volume @DEFAULT_SINK@ -5%
      bind = , XF86AudioMute, exec, pactl set-sink-mute @DEFAULT_SINK@ toggle
      bind = , XF86AudioPlay, exec, playerctl play-pause
      bind = , XF86AudioNext, exec, playerctl next
      bind = , XF86AudioPrev, exec, playerctl previous

      # Brightness
      bind = , XF86MonBrightnessUp, exec, brightnessctl set +5%
      bind = , XF86MonBrightnessDown, exec, brightnessctl set 5%-

      # Mouse bindings
      bindm = $mod, mouse:272, movewindow
      bindm = $mod, mouse:273, resizewindow
    '';
  };
}
