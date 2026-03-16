{
  config,
  lib,
  cfg,
}:

let
  inherit (config.lib.stylix) colors;
  # Extract color values without # prefix for Hyprland # background # lighter background
  base02 = lib.removePrefix "#" colors.base02; # selection background # comments/dark # dark foreground # foreground # light foreground # light background # red # orange # yellow # green # cyan
  base0D = lib.removePrefix "#" colors.base0D; # blue
  base0E = lib.removePrefix "#" colors.base0E; # purple # dark accent
in
{
  # Monitor configuration
  monitor = ",preferred,auto,1";

  # General settings
  general = {
    gaps_in = 5;
    gaps_out = 10;
    border_size = 2;
    "col.active_border" = lib.mkForce "rgba(${base0D}ee) rgba(${base0E}ee) 45deg";
    "col.inactive_border" = lib.mkForce "rgba(${base02}aa)";
    layout = "dwindle";
  };

  # Decoration settings
  decoration = {
    blur = {
      enabled = true;
      size = 3;
      passes = 1;
    };
  };

  # Animation settings
  animations =
    let
      animationConfig = {
        default = {
          enabled = true;
          bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";
          animation = [
            "windows, 1, 7, myBezier"
            "windowsOut, 1, 7, default, popin 80%"
            "border, 1, 10, default"
            "fade, 1, 7, default"
            "workspaces, 1, 6, default"
          ];
        };
        minimal = {
          enabled = true;
          bezier = "easeOutQuart, 0.25, 1, 0.5, 1";
          animation = [
            "windows, 1, 4, easeOutQuart"
            "windowsOut, 1, 4, easeOutQuart, popin 80%"
            "border, 1, 8, default"
            "fade, 1, 6, default"
            "workspaces, 1, 4, default"
          ];
        };
        fancy = {
          enabled = true;
          bezier = [
            "overshot, 0.05, 0.9, 0.1, 1.1"
            "smoothOut, 0.36, 0, 0.66, -0.56"
            "smoothIn, 0.25, 1, 0.5, 1"
          ];
          animation = [
            "windows, 1, 5, overshot, slide"
            "windowsOut, 1, 4, smoothOut, slide"
            "windowsMove, 1, 4, smoothIn"
            "border, 1, 10, default"
            "fade, 1, 10, smoothIn"
            "workspaces, 1, 6, overshot, slidevert"
          ];
        };
        none = {
          enabled = false;
        };
      };
    in
    animationConfig.${cfg.animationStyle};

  # Input settings
  input = {
    kb_layout = "us";
    follow_mouse = 1;
    sensitivity = 0.0; # -1.0 - 1.0, 0 means no modification
    touchpad = {
      natural_scroll = true;
    };
    kb_options = "ctrl:nocaps";
  };

  # Layout settings
  dwindle = {
    pseudotile = true;
    preserve_split = true;
  };

  # Misc settings
  misc = {
    force_default_wallpaper = 0;
  };

  # Hy3 plugin configuration
  plugin = lib.mkIf cfg.enableHy3 {
    hy3 = {
      tabs = {
        height = 20;
        padding = 4;
        radius = 0;
        border_width = 2;
        render_text = true;
        text_height = 8;

        "col.active" = "rgba(${base0D}ff)";
        "col.active.border" = "rgba(${base0D}ee)";
        "col.inactive" = "rgba(${base02}40)";
        "col.inactive.border" = "rgba(${base02}aa)";
      };
      autotile = {
        enable = true;
        trigger_width = 800;
        trigger_height = 500;
      };
    };
  };

  # Key bindings
  "$mod" = "SUPER";
  bind = [
    # Core bindings
    "$mod, Return, exec, ${cfg.terminal}"
    "$mod, Q, killactive"
    "$mod, M, exit"
    "$mod, E, exec, ${cfg.fileManager}"
    "$mod, V, togglefloating"

    # App launcher based on configuration
    (
      if cfg.launcher == "wofi" then
        "$mod, R, exec, wofi --show drun"
      else if cfg.launcher == "rofi" then
        "$mod, R, exec, rofi -show drun"
      else if cfg.launcher == "tofi" then
        "$mod, R, exec, tofi-drun --drun-launch=true"
      else if cfg.launcher == "fuzzel" then
        "$mod, R, exec, fuzzel"
      else if cfg.launcher == "anyrun" then
        "$mod, R, exec, anyrun"
      else
        "$mod, R, exec, wofi --show drun"
    )

    # Window/workspace management
    "$mod, P, pseudo"
    "$mod, J, togglesplit"
    "$mod, F, fullscreen, 1"
    "$mod SHIFT, F, fullscreen, 0"

    # Move focus
    "$mod, H, movefocus, l"
    "$mod, L, movefocus, r"
    "$mod, K, movefocus, u"
    "$mod, J, movefocus, d"

    # Move windows
    "$mod SHIFT, H, movewindow, l"
    "$mod SHIFT, L, movewindow, r"
    "$mod SHIFT, K, movewindow, u"
    "$mod SHIFT, J, movewindow, d"

    # Workspace switching
    "$mod, 1, workspace, 1"
    "$mod, 2, workspace, 2"
    "$mod, 3, workspace, 3"
    "$mod, 4, workspace, 4"
    "$mod, 5, workspace, 5"
    "$mod, 6, workspace, 6"
    "$mod, 7, workspace, 7"
    "$mod, 8, workspace, 8"
    "$mod, 9, workspace, 9"
    "$mod, 0, workspace, 10"

    # Move active window to workspace
    "$mod SHIFT, 1, movetoworkspace, 1"
    "$mod SHIFT, 2, movetoworkspace, 2"
    "$mod SHIFT, 3, movetoworkspace, 3"
    "$mod SHIFT, 4, movetoworkspace, 4"
    "$mod SHIFT, 5, movetoworkspace, 5"
    "$mod SHIFT, 6, movetoworkspace, 6"
    "$mod SHIFT, 7, movetoworkspace, 7"
    "$mod SHIFT, 8, movetoworkspace, 8"
    "$mod SHIFT, 9, movetoworkspace, 9"
    "$mod SHIFT, 0, movetoworkspace, 10"

    # Scroll through workspaces
    "$mod, mouse_down, workspace, e+1"
    "$mod, mouse_up, workspace, e-1"

    # Screenshots based on configuration
    (
      if cfg.screenshotTool == "grim+slurp" then
        '', Print, exec, grim -g "$(slurp)" - | wl-copy''
      else if cfg.screenshotTool == "swappy" then
        '', Print, exec, grim -g "$(slurp)" - | swappy -f -''
      else if cfg.screenshotTool == "hyprshot" then
        ", Print, exec, hyprshot -m region"
      else if cfg.screenshotTool == "grimblast" then
        ", Print, exec, grimblast copy area"
      else
        ""
    )

    # Full screenshot
    (
      if cfg.screenshotTool == "grim+slurp" then
        "SHIFT, Print, exec, grim - | wl-copy"
      else if cfg.screenshotTool == "swappy" then
        "SHIFT, Print, exec, grim - | swappy -f -"
      else if cfg.screenshotTool == "hyprshot" then
        "SHIFT, Print, exec, hyprshot -m output"
      else if cfg.screenshotTool == "grimblast" then
        "SHIFT, Print, exec, grimblast copy output"
      else
        ""
    )

    # Lock screen
    (
      if cfg.lockScreen == "swaylock" then
        "$mod ALT, L, exec, swaylock"
      else if cfg.lockScreen == "swaylock-effects" then
        "$mod ALT, L, exec, swaylock --screenshots --clock --effect-blur 7x5"
      else if cfg.lockScreen == "hyprlock" then
        "$mod ALT, L, exec, hyprlock"
      else
        ""
    )

    # Clipboard manager
    (
      if cfg.clipboardManager == "cliphist" then
        "$mod, C, exec, cliphist list | wofi --dmenu | cliphist decode | wl-copy"
      else if cfg.clipboardManager == "copyq" then
        "$mod, C, exec, copyq toggle"
      else
        ""
    )

    # Power menu
    (
      if cfg.powerMenu == "wlogout" then
        "$mod, Escape, exec, wlogout"
      else if cfg.powerMenu == "waylogout" then
        "$mod, Escape, exec, waylogout"
      else if cfg.powerMenu == "wleave" then
        "$mod, Escape, exec, wleave"
      else
        ""
    )
  ]
  ++ cfg.extraBinds;

  # Mouse bindings
  bindm = [
    "$mod, mouse:272, movewindow"
    "$mod, mouse:273, resizewindow"
  ];

  # Startup applications
  exec-once =
    (lib.optional cfg.enableWaybar "waybar")
    ++ (lib.optional cfg.enableMako "mako")
    ++ cfg.extraExecOnce;
}
