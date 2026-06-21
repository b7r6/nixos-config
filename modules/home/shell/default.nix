{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.shell;
  colors = config.hyper-modern-nixos.themes.palette;

  # Convert hex color (#RRGGBB) to ANSI truecolor escape (38;2;R;G;B)
  hexToAnsi =
    hex:
    let
      r = builtins.substring 1 2 hex;
      g = builtins.substring 3 2 hex;
      b = builtins.substring 5 2 hex;
      hexToDec =
        h:
        builtins.foldl' (
          acc: c:
          acc * 16
          + (
            if c == "a" || c == "A" then
              10
            else if c == "b" || c == "B" then
              11
            else if c == "c" || c == "C" then
              12
            else if c == "d" || c == "D" then
              13
            else if c == "e" || c == "E" then
              14
            else if c == "f" || c == "F" then
              15
            else
              builtins.fromJSON c
          )
        ) 0 (lib.stringToCharacters h);
    in
    "38;2;${toString (hexToDec r)};${toString (hexToDec g)};${toString (hexToDec b)}";

  # EZA_COLORS mapped to theme palette
  # ln=symlinks, or=orphan symlinks, di=directories, ex=executables, fi=files
  ezaColors = lib.concatStringsSep ":" [
    "di=${hexToAnsi colors.base0D}" # directories -> link blue
    "ln=${hexToAnsi colors.base0E}" # symlinks -> soft
    "or=${hexToAnsi colors.base08}" # orphan symlinks -> ice (not red!)
    "ex=${hexToAnsi colors.base0B}" # executables -> deep
    "fi=${hexToAnsi colors.base05}" # regular files -> fg
    "*.md=${hexToAnsi colors.base0E}" # markdown -> soft (not red!)
    "*.nix=${hexToAnsi colors.base0A}" # nix files -> hero
    "README*=${hexToAnsi colors.base0A}" # readme files -> hero
  ];
in
{
  imports = [ ./themed-shell.nix ];

  options.hyper-modern-nixos.shell = {
    enable = lib.mkEnableOption "shell configuration and tools";

    bash.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable bash configuration";
    };

    zsh.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable zsh configuration";
    };

    tmux.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable tmux configuration";
    };

    atuin.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Atuin shell history";
    };

    atuin.sync.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Decrypt the agenix-managed atuin sync key (atuin-key.age) to
        ~/.local/share/atuin/key so history syncs across the fleet. Off by
        default; only enable on hosts/users that should pull the shared
        history. Requires the home-manager agenix module (wired in
        configurations/home/b7r6.nix).
      '';
    };

    cliTools.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable CLI tools (bat, eza, fzf, zoxide, etc.)";
    };

    themedPrompt.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable themed shell with starship prompt";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable themed-shell module
    hyper-modern-nixos.themed-shell.enable = cfg.themedPrompt.enable;

    # Bash configuration
    programs.bash = lib.mkIf cfg.bash.enable {
      enable = true;
      enableCompletion = true;

      initExtra = ''
        # Custom bash profile goes here
      '';

      historyControl = [
        "ignoredups"
        "erasedups"
      ];

      historyFileSize = 10000;
      historySize = 10000;

      sessionVariables = {
        TERM = "xterm-256color";
        COLORTERM = "TRUECOLOR";
        COLORFGBG = "15;0";
        EZA_COLORS = ezaColors;
      };
    };

    # Zsh configuration
    programs.zsh = lib.mkIf cfg.zsh.enable {
      enable = true;
      # Lock in legacy dotDir behavior (home directory) to silence deprecation warning
      dotDir = config.home.homeDirectory;

      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      envExtra = "";
      profileExtra = "";
      loginExtra = "";
      logoutExtra = "";

      sessionVariables = {
        EZA_COLORS = ezaColors;
      };
    };

    # Atuin shell history
    programs.atuin = lib.mkIf cfg.atuin.enable {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      settings = {
        update_check = false;
        dialect = "us";
        style = "auto";
        theme = { };
      };
    };

    # Atuin sync key (agenix). Decrypt the shared key straight to atuin's key
    # path so `atuin sync` works without an interactive `atuin login`. The
    # secret is defined in secrets/secrets.nix and deployed by the home-manager
    # agenix module; never enters the nix store.
    age.secrets = lib.mkIf (cfg.atuin.enable && cfg.atuin.sync.enable) {
      atuin-key = {
        file = ../../../secrets/agenix/users/b7r6/atuin-key.age;
        path = "${config.home.homeDirectory}/.local/share/atuin/key";
        mode = "600";
      };
    };

    # Tmux configuration
    programs.tmux = lib.mkIf cfg.tmux.enable {
      enable = true;
      prefix = "C-o";
      terminal = "tmux-256color";
      escapeTime = 10;
      historyLimit = 10000;
      keyMode = "emacs";
      baseIndex = 1;
      mouse = true;
      clock24 = true;
      sensibleOnTop = false;

      extraConfig = ''
        # Force tmux to spawn login shells so bashrc gets sourced
        set -g default-command "${pkgs.bashInteractive}/bin/bash -l"

        # well-supported terminal type that works virtually everywhere
        set -g default-terminal "tmux-256color"

        # Enable RGB/truecolor for tmux's own terminal type
        set -ga terminal-features ",tmux-256color:RGB"

        # Enable truecolor for outer terminals that support it
        set -ga terminal-overrides ",xterm-256color:Tc:RGB"
        set -ga terminal-overrides ",*-256color:Tc:RGB"
        set -ga terminal-overrides ",alacritty:RGB"
        set -ga terminal-overrides ",wezterm:RGB"
        set -ga terminal-overrides ",ghostty:Tc:RGB"
        set -ga terminal-overrides ",xterm-ghostty:Tc:RGB"

        # Kitty graphics protocol passthrough
        set -ga terminal-features ",xterm-ghostty:RGB:sixel"
        set -ga terminal-features ",ghostty:RGB:sixel"

        # Ensure SSH_TTY is updated in new windows
        set -ag update-environment "SSH_TTY"

        # ── Cursor: always a blinking block, even inside tmux ──────────────────
        # Inside tmux, TMUX owns the cursor — ghostty's cursor-style never reaches
        # the screen. Two fixes:
        #  1. Teach tmux that the outer terminals CAN set the cursor shape, by
        #     adding the DECSCUSR Ss/Se capabilities to their overrides (the
        #     tmux-256color terminfo lacks them), so shape escapes pass through.
        #  2. Pin tmux's OWN cursor to a blinking block (tmux 3.2+ cursor-style),
        #     so even at the tmux layer with no app driving it, it's a block.
        set -ga terminal-overrides ',xterm-ghostty:Ss=\E[%p1%d q:Se=\E[ q'
        set -ga terminal-overrides ',ghostty:Ss=\E[%p1%d q:Se=\E[ q'
        set -ga terminal-overrides ',xterm-256color:Ss=\E[%p1%d q:Se=\E[ q'
        set -g cursor-style blinking-block

        # Enable passthrough for escape sequences (needed for kitty graphics)
        set -g allow-passthrough all

        # prevent display glitches with careful refresh settings
        set -g focus-events on
        set -g status-interval 5

        # ensure shell integration works properly
        set -g allow-rename on
        set -g set-titles on

        # KEY BINDINGS - Emacs Centric Defaults
        unbind '"'
        unbind %
        bind-key n next-window
        bind-key p previous-window
        bind-key C-o last-window
        bind-key C-n select-pane -t :.+
        bind-key C-p select-pane -t :.-
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"
        bind r source-file ~/.config/tmux/tmux.conf \; display "Reloaded!"

        # simple styles to avoid potential rendering issues
        set -g message-style "fg=${colors.base05},bg=${colors.base01}"
        set -g mode-style "fg=${colors.base05},bg=${colors.base03}"

        # simple border style that works in most/all terminals
        set -g pane-border-lines heavy
        set -g pane-active-border-style "fg=${colors.base03}"
        set -g pane-border-style "fg=${colors.base03}"

        # simple status bar that works almost everywhere
        set -g status-left ""

        set -g status-right-length 150
        set -g status-justify right
        set -g status-style "fg=${colors.base03},bg=${colors.base01}"
        set -g status-right " #[fg=${colors.base0D}]%H:%M #[fg=${colors.base0D}]#h#[default] #[fg=${colors.base0D}]#(whoami)#[default] "

        set -g window-status-separator ""
        set -g window-status-current-format " #[fg=${colors.base05},bg=default]#W#[default]"
        set -g window-status-format " #[fg=${colors.base03}]#W#[default] "
      '';
    };

    # CLI tools
    programs.bat = lib.mkIf cfg.cliTools.enable {
      enable = true;
      config = {
        italic-text = "never";
        style = "plain";
      };
    };

    programs.eza = lib.mkIf cfg.cliTools.enable {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      extraOptions = [
        "--color=always"
        "--group-directories-first"
        "--icons"
      ];
    };

    programs.fzf = lib.mkIf cfg.cliTools.enable {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    programs.zoxide = lib.mkIf cfg.cliTools.enable {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    programs.direnv = lib.mkIf cfg.cliTools.enable {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
      config.global.hide_env_diff = true;
    };

    programs.starship = lib.mkIf cfg.cliTools.enable {
      enable = true;

      settings = {
        username = {
          style_user = "blue bold";
          style_root = "red bold";
          format = "[$user]($style) ";
          disabled = false;
          show_always = true;
        };

        hostname = {
          ssh_only = false;
          ssh_symbol = "🌐 ";
          format = "on [$hostname](bold red) ";
          trim_at = ".local";
          disabled = false;
        };
      };
    };

    programs.jq.enable = lib.mkIf cfg.cliTools.enable true;
    programs.btop.enable = lib.mkIf cfg.cliTools.enable true;
    programs.tmate = lib.mkIf cfg.cliTools.enable { enable = true; };

    # Shell packages
    home.packages = lib.mkIf cfg.cliTools.enable (
      with pkgs;
      [
        bat
        btop
        direnv
        duf
        dust
        eza
        fd
        git
        glow
        gnumake
        htop
        jq
        less
        nix-info
        nixd
        nixfmt
        ripgrep
        sd
        tree
        viddy
        vivid
        zoxide
      ]
    );
  };
}
