# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // hyprland
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#
# Hyprland window manager configuration with high-level abstractions.
#
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    types
    mkIf
    mkMerge
    mapAttrsToList
    ;

  cfg = config.hyper-modern-nixos.hyprland;
  colors = config.lib.stylix.colors;

  # ── Monitor Type ────────────────────────────────────────────────────────────
  
  monitorType = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        description = "Monitor description (from `hyprctl monitors`)";
        example = "ASUSTek COMPUTER INC PG32UCDP SCLMQS022729";
      };

      resolution = mkOption {
        type = types.str;
        default = "preferred";
        description = "Resolution (e.g., '3840x2160' or 'preferred')";
      };

      refreshRate = mkOption {
        type = types.int;
        default = 120;
        description = "Refresh rate in Hz";
      };

      position = mkOption {
        type = types.either (types.enum [
          "auto"
          "auto-left"
          "auto-right"
          "auto-up"
          "auto-down"
        ]) types.str;
        
        default = "auto";
        
        description = ''
          Monitor position. Use:
          - "auto" - automatic placement
          - "auto-left" - place to the left of existing monitors
          - "auto-right" - place to the right of existing monitors
          - "auto-up" / "auto-down" - vertical placement
          - "0x0", "1920x0", etc. - explicit pixel coordinates
        '';
        
        example = "auto-left";
      };

      scale = mkOption {
        type = types.float;
        default = 1.0;
        description = "Display scale factor";
      };

      workspaces = mkOption {
        type = types.listOf types.int;
        default = [ ];
        description = "Workspaces assigned to this monitor";
        example = [
          1
          2
          3
          4
          5
        ];
      };

      primary = mkOption {
        type = types.bool;
        default = false;
        description = "Is this the primary monitor?";
      };
    };
  };

  # ── App Launcher Type ───────────────────────────────────────────────────────
  
  appType = types.submodule {
    options = {
      terminal = mkOption {
        type = types.str;
        default = "ghostty";
        description = "Terminal emulator command";
      };

      launcher = mkOption {
        type = types.str;
        default = "wofi --show drun";
        description = "Application launcher command";
      };

      browser = mkOption {
        type = types.str;
        default = "firefox";
        description = "Web browser command";
      };

      fileManager = mkOption {
        type = types.str;
        default = "nemo";
        description = "File manager command";
      };

      lockScreen = mkOption {
        type = types.str;
        default = "swaylock";
        description = "Lock screen command";
      };
    };
  };

  # ── Appearance Type ─────────────────────────────────────────────────────────
  
  appearanceType = types.submodule {
    options = {
      gaps = {
        inner = mkOption {
          type = types.int;
          default = 4;
          description = "Gap between windows";
        };
        outer = mkOption {
          type = types.int;
          default = 8;
          description = "Gap between windows and screen edge";
        };
      };

      border = {
        size = mkOption {
          type = types.int;
          default = 2;
          description = "Window border size in pixels";
        };
        radius = mkOption {
          type = types.int;
          default = 0;
          description = "Window corner radius";
        };
      };

      opacity = {
        active = mkOption {
          type = types.float;
          default = 1.0;
          description = "Active window opacity";
        };
        inactive = mkOption {
          type = types.float;
          default = 0.85;
          description = "Inactive window opacity";
        };
      };

      blur = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable window blur";
        };
        size = mkOption {
          type = types.int;
          default = 8;
          description = "Blur size";
        };
        passes = mkOption {
          type = types.int;
          default = 2;
          description = "Number of blur passes";
        };
      };

      animations = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable animations";
        };
        speed = mkOption {
          type = types.enum [
            "fast"
            "normal"
            "slow"
          ];
          default = "fast";
          description = "Animation speed preset";
        };
      };
    };
  };

  # ── Input Type ──────────────────────────────────────────────────────────────
  
  inputType = types.submodule {
    options = {
      keyboard = {
        layout = mkOption {
          type = types.str;
          default = "us";
          description = "Keyboard layout";
        };
        
        options = mkOption {
          type = types.str;
          default = "ctrl:nocaps";
          description = "XKB options (e.g., 'ctrl:nocaps')";
        };
      };

      mouse = {
        sensitivity = mkOption {
          type = types.float;
          default = 0.0;
          description = "Mouse sensitivity (-1.0 to 1.0)";
        };
        
        accelProfile = mkOption {
          type = types.enum [
            "flat"
            "adaptive"
          ];
          
          default = "flat";
          description = "Mouse acceleration profile";
        };
      };

      touchpad = {
        naturalScroll = mkOption {
          type = types.bool;
          default = true;
          description = "Natural (inverted) scrolling";
        };
        
        tapToClick = mkOption {
          type = types.bool;
          default = true;
          description = "Tap to click";
        };
      };
    };
  };

  # ── Window Rule Type ────────────────────────────────────────────────────────
  
  windowRuleType = types.submodule {
    options = {
      match = mkOption {
        type = types.str;
        description = "Window match pattern (class, title, etc.)";
        example = "class:^(firefox)$";
      };
      rules = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Rules to apply";
        example = [
          "workspace 5"
          "float"
        ];
      };
    };
  };

  # ── Helper Functions ────────────────────────────────────────────────────────

  # Generate hyprland monitor config string
  mkMonitorConfig =
    _name: mon:
    "desc:${mon.description},${mon.resolution}@${toString mon.refreshRate},${mon.position},${toString mon.scale}";

  # Generate workspace bindings
  mkWorkspaceBindings =
    monitors:
    lib.flatten (
      mapAttrsToList (
        _name: mon:
        map (ws: "${toString ws}, monitor:desc:${mon.description}, persistent:true") mon.workspaces
      ) monitors
    );

  # Animation speed multipliers
  animationSpeed = {
    fast = 3;
    normal = 5;
    slow = 8;
  };

in
{
  # Using home-manager's built-in hyprland module with nixpkgs hyprland

  options.hyper-modern-nixos.hyprland = {
    enable = mkEnableOption "Hyprland window manager";

    # ── Monitors ──────────────────────────────────────────────────────────────

    monitors = mkOption {
      type = types.attrsOf monitorType;
      default = { };
      description = "Monitor configurations";

      example = {
        left = {
          description = "ASUSTek COMPUTER INC PG32UCDP SCLMQS022729";
          resolution = "3840x2160";
          refreshRate = 240;
          position = "0x0";
          scale = 1.5;
          workspaces = [
            1
            2
            3
            4
            5
          ];
          primary = true;
        };
        right = {
          description = "ASUSTek COMPUTER INC PG32UCDP T1LMQS044820";
          resolution = "3840x2160";
          refreshRate = 240;
          position = "2560x0";
          scale = 1.5;
          workspaces = [
            6
            7
            8
            9
            10
          ];
        };
      };
    };

    # ── Applications ──────────────────────────────────────────────────────────

    apps = mkOption {
      type = appType;
      default = { };
      description = "Default applications";
    };

    # ── Appearance ────────────────────────────────────────────────────────────

    appearance = mkOption {
      type = appearanceType;
      default = { };
      description = "Visual appearance settings";
    };

    # ── Input ─────────────────────────────────────────────────────────────────

    input = mkOption {
      type = inputType;
      default = { };
      description = "Input device settings";
    };

    # ── Window Rules ──────────────────────────────────────────────────────────

    windowRules = mkOption {
      type = types.listOf windowRuleType;
      default = [ ];
      description = "Window rules for automatic placement/behavior";
      example = [
        {
          match = "class:^(firefox)$";
          rules = [ "workspace 5" ];
        }
        {
          match = "class:^(pavucontrol)$";
          rules = [
            "float"
            "center"
          ];
        }
      ];
    };

    # ── Autostart ─────────────────────────────────────────────────────────────

    autostart = mkOption {
      type = types.listOf types.str;
      default = [
        "hyprpaper"
        "mako"
        "blueman-applet"
        "nm-applet"
      ];
      description = "Programs to start on login";
    };

    # ── Keybinding Preset ─────────────────────────────────────────────────────

    keybindings = {
      preset = mkOption {
        type = types.enum [
          "vim"
          "emacs"
          "arrows"
        ];
        default = "vim";
        description = "Navigation keybinding style";
      };

      mod = mkOption {
        type = types.str;
        default = "SUPER";
        description = "Primary modifier key";
      };

      extraBinds = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional custom keybindings";
      };
    };

    # ── Plugins ───────────────────────────────────────────────────────────────

    plugins = {
      hy3.enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable hy3 tiling plugin (i3-like)";
      };
    };

    # ── Advanced ──────────────────────────────────────────────────────────────

    extraConfig = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Extra hyprland settings (merged with generated config)";
    };
  };

  config = mkIf cfg.enable {
    # This is the canonical Hyprland configuration module.

    wayland.windowManager.hyprland = {
      enable = true;
      configType = "hyprlang";
      systemd.enable = true;
      package = pkgs.hyprland;

      plugins = lib.optional cfg.plugins.hy3.enable pkgs.hyprlandPlugins.hy3;

      settings = mkMerge [
        {
          # ── Monitors ────────────────────────────────────────────────────────

          monitor = mapAttrsToList mkMonitorConfig cfg.monitors;
          workspace = mkWorkspaceBindings cfg.monitors;

          # ── Autostart ───────────────────────────────────────────────────────

          exec-once = cfg.autostart;

          # ── General ─────────────────────────────────────────────────────────

          general = {
            border_size = cfg.appearance.border.size;
            gaps_in = cfg.appearance.gaps.inner;
            gaps_out = cfg.appearance.gaps.outer;
            layout = if cfg.plugins.hy3.enable then "hy3" else "dwindle";
            resize_on_border = true;

            "col.active_border" =
              lib.mkForce "rgba(${lib.removePrefix "#" colors.base0D}ff) rgba(${lib.removePrefix "#" colors.base0E}ff) 45deg";
            "col.inactive_border" = lib.mkForce "rgba(${lib.removePrefix "#" colors.base02}66)";
          };

          # ── Decoration ──────────────────────────────────────────────────────

          decoration = {
            rounding = cfg.appearance.border.radius;

            blur = {
              enabled = cfg.appearance.blur.enable;
              size = cfg.appearance.blur.size;
              passes = cfg.appearance.blur.passes;
              new_optimizations = true;
              xray = true;
              ignore_opacity = false;
            };

            active_opacity = cfg.appearance.opacity.active;
            inactive_opacity = cfg.appearance.opacity.inactive;
            fullscreen_opacity = 1.0;
          };

          # ── Animations ──────────────────────────────────────────────────────

          animations = {
            enabled = cfg.appearance.animations.enable;

            bezier = [
              "easeOutQuint,   0.22, 1, 0.36, 1"
              "easeInOutQuint, 0.83, 0, 0.17, 1"
              "easeOutExpo,    0.16, 1, 0.3,  1"
            ];

            animation =
              let
                speed = animationSpeed.${cfg.appearance.animations.speed};
              in
              [
                "windows,          1, ${toString speed},       easeOutExpo, popin 80%"
                "windowsOut,       1, ${toString speed},       easeOutExpo, popin 80%"
                "border,           1, ${toString (speed + 2)}, easeOutQuint"
                "fade,             1, ${toString speed},       easeInOutQuint"
                "workspaces,       1, ${toString speed},       easeOutExpo, slide"
                "specialWorkspace, 1, ${toString speed},       easeOutExpo, slidevert"
              ];
          };

          # ── Input ───────────────────────────────────────────────────────────

          input = {
            kb_layout = cfg.input.keyboard.layout;
            kb_options = cfg.input.keyboard.options;
            follow_mouse = 1;
            sensitivity = cfg.input.mouse.sensitivity;
            accel_profile = cfg.input.mouse.accelProfile;
            mouse_refocus = false;

            touchpad = {
              natural_scroll = cfg.input.touchpad.naturalScroll;
              disable_while_typing = true;
              clickfinger_behavior = true;
              tap-to-click = cfg.input.touchpad.tapToClick;
              drag_lock = true;
            };
          };

          # ── Gestures ────────────────────────────────────────────────────────

          gestures = {
            # workspace_swipe = true;
            # workspace_swipe_fingers = 3;
            workspace_swipe_distance = 300;
            workspace_swipe_invert = false;
            workspace_swipe_create_new = false;
          };

          # ── Misc ────────────────────────────────────────────────────────────

          misc = {
            force_default_wallpaper = 0;
            animate_mouse_windowdragging = false;
            animate_manual_resizes = false;
            enable_swallow = true;
            swallow_regex = "^(wezterm|ghostty|alacritty|foot|kitty)$";
            focus_on_activate = true;
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            vrr = 1;
            mouse_move_enables_dpms = true;
            key_press_enables_dpms = true;
          };

          # ── hy3 Plugin ──────────────────────────────────────────────────────

          "plugin:hy3" = mkIf cfg.plugins.hy3.enable {
            tabs = {
              height = 20;
              padding = 4;
              from_top = true;
              radius = 0;
              render_text = true;
              text_font = config.stylix.fonts.monospace.name;
              text_height = 10;

              "col.active" = "rgba(${lib.removePrefix "#" colors.base0D}ff)";
              "col.inactive" = "rgba(${lib.removePrefix "#" colors.base01}ff)";
              "col.active.text" = "rgba(${lib.removePrefix "#" colors.base00}ff)";
              "col.inactive.text" = "rgba(${lib.removePrefix "#" colors.base04}ff)";
            };

            autotile = {
              enable = true;
              trigger_width = 800;
              trigger_height = 500;
            };
          };

          # ── Variables ───────────────────────────────────────────────────────

          "$mod" = cfg.keybindings.mod;
          "$alt" = "ALT";
          "$terminal" = cfg.apps.terminal;
          "$browser" = cfg.apps.browser;
          "$fileManager" = cfg.apps.fileManager;
          "$launcher" = cfg.apps.launcher;
          "$lockScreen" = cfg.apps.lockScreen;

          # ── Keybindings ─────────────────────────────────────────────────────

          bind =
            let
              # Navigation keys based on preset
              nav =
                {
                  vim = {
                    left = "H";
                    down = "J";
                    up = "K";
                    right = "L";
                  };

                  emacs = {
                    left = "B";
                    down = "N";
                    up = "P";
                    right = "F";
                  };

                  arrows = {
                    left = "Left";
                    down = "Down";
                    up = "Up";
                    right = "Right";
                  };
                }
                .${cfg.keybindings.preset};

              # Movement commands based on hy3 or default
              moveFocus = dir: if cfg.plugins.hy3.enable then "hy3:movefocus, ${dir}" else "movefocus, ${dir}";
              moveWindow = dir: if cfg.plugins.hy3.enable then "hy3:movewindow, ${dir}" else "movewindow, ${dir}";
            in
            [
              # ── Core ──────────────────────────────────────────────────────

              "$mod, Return, exec, $terminal"
              "$mod, E, exec, $fileManager"
              "$mod, W, exec, $browser"
              "$mod, Space, exec, $launcher"
              "$mod, BackSpace, killactive"
              "$mod SHIFT, BackSpace, exit"
              "$mod, Escape, exec, $lockScreen"

              # ── Window States ─────────────────────────────────────────────

              "$mod, F, fullscreen, 0"
              "$mod SHIFT, F, fullscreen, 1"
              "$mod, D, togglefloating"
              "$mod, P, pin"
              "$mod, C, centerwindow"

              # ── Navigation ────────────────────────────────────────────────

              "$mod, ${nav.left}, ${moveFocus "l"}"
              "$mod, ${nav.right}, ${moveFocus "r"}"
              "$mod, ${nav.up}, ${moveFocus "u"}"
              "$mod, ${nav.down}, ${moveFocus "d"}"

              # ── Move Windows ──────────────────────────────────────────────

              "$mod SHIFT, ${nav.left}, ${moveWindow "l"}"
              "$mod SHIFT, ${nav.right}, ${moveWindow "r"}"
              "$mod SHIFT, ${nav.up}, ${moveWindow "u"}"
              "$mod SHIFT, ${nav.down}, ${moveWindow "d"}"

              # ── Resize Windows ────────────────────────────────────────────

              "$mod $alt, ${nav.left}, resizeactive, -30 0"
              "$mod $alt, ${nav.right}, resizeactive, 30 0"
              "$mod $alt, ${nav.up}, resizeactive, 0 -30"
              "$mod $alt, ${nav.down}, resizeactive, 0 30"

              # ── Workspaces ────────────────────────────────────────────────
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

              # ── Workspaces 11-15 (right monitor) ───────────────────────

              "$mod CTRL, 1, workspace, 11"
              "$mod CTRL, 2, workspace, 12"
              "$mod CTRL, 3, workspace, 13"
              "$mod CTRL, 4, workspace, 14"
              "$mod CTRL, 5, workspace, 15"

              "$mod SHIFT CTRL, 1, movetoworkspace, 11"
              "$mod SHIFT CTRL, 2, movetoworkspace, 12"
              "$mod SHIFT CTRL, 3, movetoworkspace, 13"
              "$mod SHIFT CTRL, 4, movetoworkspace, 14"
              "$mod SHIFT CTRL, 5, movetoworkspace, 15"

              "$mod, Tab, workspace, m+1"
              "$mod SHIFT, Tab, workspace, m-1"

              # ── Monitor Controls ──────────────────────────────────────────
              "$mod, comma, focusmonitor, -1"
              "$mod, period, focusmonitor, +1"
              "$mod SHIFT, comma, movewindow, mon:-1"
              "$mod SHIFT, period, movewindow, mon:+1"
              "$mod $alt, comma, movecurrentworkspacetomonitor, -1"
              "$mod $alt, period, movecurrentworkspacetomonitor, +1"
              "$mod $alt, S, swapactiveworkspaces, +1 current"

              # ── Screenshots ───────────────────────────────────────────────
              "$mod, S, exec, grimblast copy area"
              "$mod SHIFT, S, exec, grimblast save area ~/Screenshots/$(date +'%Y-%m-%d_%H-%M-%S').png"
              "$mod SHIFT $alt, S, exec, grimblast copy screen"

              # ── Media ─────────────────────────────────────────────────────
              ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
              ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
              ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
              ", XF86AudioPlay, exec, playerctl play-pause"
              ", XF86AudioNext, exec, playerctl next"
              ", XF86AudioPrev, exec, playerctl previous"
              ", XF86MonBrightnessUp, exec, brightnessctl set +5%"
              ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
            ]
            ++ (lib.optionals cfg.plugins.hy3.enable [
              # ── hy3 Layout ────────────────────────────────────────────────
              "$mod, V, hy3:makegroup, v"
              "$mod, B, hy3:makegroup, h"
              "$mod, T, hy3:makegroup, tab"
              "$mod, G, hy3:changegroup, toggletab"
              "$mod, A, hy3:changefocus, raise"
              "$mod SHIFT, A, hy3:changefocus, lower"
              "$mod SHIFT, G, hy3:changegroup, opposite"
            ])
            ++ cfg.keybindings.extraBinds;

          # ── Mouse Bindings ──────────────────────────────────────────────────
          bindm = [
            "$mod, mouse:272, movewindow"
            "$mod, mouse:273, resizewindow"
            "$mod SHIFT, mouse:272, resizewindow"
          ];

          # ── Window Rules ────────────────────────────────────────────────────
          # windowrulev2 =
          #   lib.flatten (map (rule: map (r: "${r}, ${rule.match}") rule.rules) cfg.windowRules)
          #   ++ [
          #     # Default float rules
          #     "float, class:^(pavucontrol)$"
          #     "float, class:^(nm-connection-editor)$"
          #     "float, class:^(.blueman-manager-wrapped)$"
          #     "float, title:^(Picture-in-Picture)$"
          #     "pin, title:^(Picture-in-Picture)$"
          #   ];
        }

        # Merge extra config
        cfg.extraConfig
      ];
    };

    # ── Packages ──────────────────────────────────────────────────────────────

    home.packages = with pkgs; [
      blueman
      brightnessctl
      cliphist
      grim
      grimblast
      hyprpaper
      hyprpicker
      jq
      libnotify
      networkmanagerapplet
      pamixer
      pavucontrol
      playerctl
      slurp
      swappy
      swaybg
      swayidle
      wdisplays
      wev
      wf-recorder
      wl-clipboard
      wlr-randr
      wlsunset
    ];

    # ── Hyprpaper ─────────────────────────────────────────────────────────────

    xdg.configFile."hypr/hyprpaper.conf".text = ''
      preload = ~/.config/wallpaper.png
      wallpaper = ,~/.config/wallpaper.png
      splash = false
    '';
  };
}
