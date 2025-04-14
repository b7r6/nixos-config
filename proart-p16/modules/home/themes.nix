# System-wide theme configuration 
{ config, lib, pkgs, flake, ... }:

let
  inherit (flake) inputs;
  
  # Create a proper derivation for Berkeley Mono
  berkeley-mono = pkgs.stdenv.mkDerivation {
    name = "berkeley-mono-font";
    # Assuming Berkeley Mono is a zip file in ~/Downloads
    src = builtins.path { 
      path = ../../berekelyMono.zip; 
      name = "berkeley-mono-zip";
    };

    # Required build inputs for handling zip files
    nativeBuildInputs = with pkgs; [ unzip ];

    unpackPhase = ''
      unzip $src
    '';

    installPhase = ''
      mkdir -p $out/share/fonts/opentype
      cp *.otf $out/share/fonts/opentype/
    '';

    meta = with lib; {
      description = "Berkeley Mono Font";
      license = licenses.unfree;
      platforms = platforms.all;
    };
  };
  
  # Ono-Sendai Hypermodern Blue theme
  onoSendaiTheme = {
    slug = "ono-sendai-hypermodern-blue";
    name = "Ono Sendai Hypermodern Blue";
    author = "b7r6";
    variant = "dark";

    # Core colors for the theme
    colors = {
      # Main background and foreground
      background = "#0a0e14";
      backgroundDark = "#050a10";
      backgroundLight = "#10151d";
      foreground = "#b3b1ad";
      
      # Accent colors
      accentPrimary = "#39bae6";
      accentSecondary = "#59c2ff";
      accentTertiary = "#6dcbfa";
      
      # Text colors
      textPrimary = "#e6e1cf";
      textSecondary = "#b3b1ad";
      textTertiary = "#626a73";
      textSelection = "#173043";
      
      # UI element colors
      border = "#101521";
      activeBorder = "#39bae6";
      separator = "#1d232f";
      
      # Terminal colors
      black = "#0a0e14";
      red = "#ff3333";
      green = "#c2d94c";
      yellow = "#ffb454";
      blue = "#59c2ff";
      magenta = "#f07178";
      cyan = "#39bae6";
      white = "#e6e1cf";
      brightBlack = "#626a73";
      brightRed = "#ff6666";
      brightGreen = "#d8ee91";
      brightYellow = "#ffd580";
      brightBlue = "#80cbff";
      brightMagenta = "#f99da7";
      brightCyan = "#7ddde6";
      brightWhite = "#ffffff";
    };
    
    # Map to GTK CSS variables
    gtk = {
      theme_name = "Adwaita-dark";
      icon_theme_name = "Papirus-Dark";
      cursor_theme_name = "Adwaita";
      font_name = "Berkeley Mono SemiBold 11";
      applications_prefer_dark_theme = true;
      
      gtk3 = {
        settings = {
          gtk-theme-name = "Adwaita-dark";
          gtk-icon-theme-name = "Papirus-Dark";
          gtk-font-name = "Berkeley Mono SemiBold 11";
          gtk-cursor-theme-name = "Adwaita";
          gtk-application-prefer-dark-theme = true;
          gtk-cursor-theme-size = 24;
          gtk-toolbar-style = "GTK_TOOLBAR_BOTH";
          gtk-toolbar-icon-size = "GTK_ICON_SIZE_LARGE_TOOLBAR";
          gtk-button-images = 1;
          gtk-menu-images = 1;
          gtk-enable-event-sounds = 1;
          gtk-enable-input-feedback-sounds = 0;
          gtk-xft-antialias = 1;
          gtk-xft-hinting = 1;
          gtk-xft-hintstyle = "hintfull";
          gtk-xft-rgba = "rgb";
        };
      };
    };
    
    # Terminal colors
    terminal = {
      background = "#0a0e14";
      foreground = "#b3b1ad";
      cursor = "#39bae6";
      selection_background = "#173043";
      selection_foreground = "#b3b1ad";
      
      # Normal colors
      black = "#0a0e14";
      red = "#ff3333";
      green = "#c2d94c";
      yellow = "#ffb454";
      blue = "#59c2ff";
      magenta = "#f07178";
      cyan = "#39bae6";
      white = "#e6e1cf";
      
      # Bright colors
      bright_black = "#626a73";
      bright_red = "#ff6666";
      bright_green = "#d8ee91";
      bright_yellow = "#ffd580";
      bright_blue = "#80cbff";
      bright_magenta = "#f99da7";
      bright_cyan = "#7ddde6";
      bright_white = "#ffffff";
    };
    
    # Hyprland colors
    hyprland = {
      active_border = "rgba(39BAE6ff)";
      inactive_border = "rgba(10152180)";
      group_border = "rgba(10152180)";
      group_border_active = "rgba(39BAE6ff)";
    };
  };
in
{
  options.themes = {
    enable = lib.mkEnableOption "Enable system-wide theme support";
  };

  # Make colors available to other modules through an option
  options.themes.colors = lib.mkOption {
    type = lib.types.attrs;
    description = "The theme colors for use in configurations";
    internal = true;
    readOnly = true;
    default = {};
  };

  config = lib.mkIf config.themes.enable {
    # Import required modules
    home.packages = with pkgs; [
      # Add theme-related packages
      berkeley-mono
      papirus-icon-theme
      adwaita-qt
      qt5ct
      libsForQt5.qtstyleplugin-kvantum
      
      # Font tools
      font-manager
      fontconfig
    ];
    
    # Configure GTK
    gtk = {
      enable = true;
      theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome.gnome-themes-extra;
      };
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
      font = {
        name = "Berkeley Mono SemiBold";
        size = 11;
        package = berkeley-mono;
      };
      gtk3.extraConfig = {
        gtk-application-prefer-dark-theme = true;
      };
      gtk4.extraConfig = {
        gtk-application-prefer-dark-theme = true;
      };
    };
    
    # Configure QT
    qt = {
      enable = true;
      platformTheme = "gtk";
      style = {
        name = "adwaita-dark";
        package = pkgs.adwaita-qt;
      };
    };
    
    # Configure cursor
    home.pointerCursor = {
      name = "Adwaita";
      package = pkgs.gnome.adwaita-icon-theme;
      size = 24;
      gtk.enable = true;
      x11.enable = true;
    };
    
    # Configure terminal colors for common terminals
    programs.alacritty.settings.colors = with onoSendaiTheme.terminal; {
      primary = {
        inherit background foreground;
      };
      normal = {
        inherit black red green yellow blue magenta cyan white;
      };
      bright = {
        black = bright_black;
        red = bright_red;
        green = bright_green;
        yellow = bright_yellow;
        blue = bright_blue;
        magenta = bright_magenta;
        cyan = bright_cyan;
        white = bright_white;
      };
    };
    
    # Configure WezTerm colors
    programs.wezterm.extraConfig = ''
      return {
        colors = {
          foreground = "${onoSendaiTheme.terminal.foreground}",
          background = "${onoSendaiTheme.terminal.background}",
          cursor_bg = "${onoSendaiTheme.terminal.cursor}",
          cursor_fg = "${onoSendaiTheme.terminal.background}",
          cursor_border = "${onoSendaiTheme.terminal.cursor}",
          selection_fg = "${onoSendaiTheme.terminal.selection_foreground}",
          selection_bg = "${onoSendaiTheme.terminal.selection_background}",
          ansi = {
            "${onoSendaiTheme.terminal.black}",
            "${onoSendaiTheme.terminal.red}",
            "${onoSendaiTheme.terminal.green}",
            "${onoSendaiTheme.terminal.yellow}",
            "${onoSendaiTheme.terminal.blue}",
            "${onoSendaiTheme.terminal.magenta}",
            "${onoSendaiTheme.terminal.cyan}",
            "${onoSendaiTheme.terminal.white}",
          },
          brights = {
            "${onoSendaiTheme.terminal.bright_black}",
            "${onoSendaiTheme.terminal.bright_red}",
            "${onoSendaiTheme.terminal.bright_green}",
            "${onoSendaiTheme.terminal.bright_yellow}",
            "${onoSendaiTheme.terminal.bright_blue}",
            "${onoSendaiTheme.terminal.bright_magenta}",
            "${onoSendaiTheme.terminal.bright_cyan}",
            "${onoSendaiTheme.terminal.bright_white}",
          },
        },
      }
    '';
    
    # Configure Hyprland colors
    wayland.windowManager.hyprland.settings = {
      general = {
        col.active_border = onoSendaiTheme.hyprland.active_border;
        col.inactive_border = onoSendaiTheme.hyprland.inactive_border;
      };
      group = {
        col.border_active = onoSendaiTheme.hyprland.group_border_active;
        col.border_inactive = onoSendaiTheme.hyprland.group_border;
      };
    };
    
    # Configure font defaults
    fonts.fontconfig = {
      enable = true;
      defaultFonts = {
        monospace = [ "Berkeley Mono SemiBold" ];
        sansSerif = [ "Berkeley Mono SemiBold" ];
        serif = [ "Berkeley Mono SemiBold" ];
      };
    };
    
    # Create wallpaper
    home.file.".config/wallpaper.png".source = 
      let
        wallpaper = pkgs.stdenv.mkDerivation {
          name = "ono-sendai-wallpaper";
          phases = [ "installPhase" ];
          installPhase = ''
            mkdir -p $out
            ${pkgs.imagemagick}/bin/convert -size 3840x2160 \
              gradient:'${onoSendaiTheme.colors.backgroundDark}-${onoSendaiTheme.colors.background}' \
              -fill '${onoSendaiTheme.colors.accentPrimary}' \
              -pointsize 24 -font "Berkeley-Mono-SemiBold" \
              -gravity southeast -annotate +50+50 "ONO-SENDAI HYPERMODERN" \
              $out/wallpaper.png
          '';
        };
      in
      "${wallpaper}/wallpaper.png";
    
    # Configure Hyprpaper
    home.file.".config/hypr/hyprpaper.conf".text = ''
      preload = ~/.config/wallpaper.png
      wallpaper = ,~/.config/wallpaper.png
    '';
    
    # Make colors available to other modules
    themes.colors = onoSendaiTheme.colors;
  };
} 