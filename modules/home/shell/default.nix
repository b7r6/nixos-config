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
        COLORTERM = "truecolor";
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
        # Theme is WRITTEN BY WINTERMUTE (config/atuin/themes/wintermute.toml)
        # on every reconcile; atuin re-reads it each `atuin search`, so Ctrl-R
        # retints live. Seeded below if absent (cold start before the daemon).
        theme.name = "wintermute";
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
    # ── zellij: the modern multiplexer, tmux muscle memory intact ──────────
    # Config is repo-homed (dotfiles/zellij, hot-reloaded by zellij on edit);
    # the theme file is WRITTEN BY WINTERMUTE on every reconcile and seeded
    # here only if absent (cold start before the daemon has run). tmux stays
    # fully configured during the transition — both run side by side.
    home.file.".config/zellij/config.kdl".source =
      config.lib.file.mkOutOfStoreSymlink "${config.hyper-modern-nixos.dotfiles.path}/zellij/config.kdl";

    # layouts are repo-homed too (hot-edit like the config)
    home.file.".config/zellij/layouts".source =
      config.lib.file.mkOutOfStoreSymlink "${config.hyper-modern-nixos.dotfiles.path}/zellij/layouts";

    # zjstatus — the bar plugin the hypermodern layout drives (pinned wasm
    # release; not in the nixpkgs fork)
    home.file.".config/zellij/plugins/zjstatus.wasm".source = pkgs.fetchurl {
      url = "https://github.com/dj95/zjstatus/releases/download/v0.24.0/zjstatus.wasm";
      sha256 = "16v6ascpyl7na6lp3v98haggp9lwsg6r1rlv40zcyqpd3p7dxkhw";
    };

    # Hand-placed plugin wasm (e.g. dropped in live before a switch) is a
    # reproducible cache artifact — clear it so linkGeneration never trips
    # over an unmanaged regular file. Symlinks are home-manager's own.
    home.activation.zellijPluginMigrate = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      for _f in "${config.xdg.configHome}/zellij/plugins/zjstatus.wasm" \
                "${config.xdg.configHome}/zellij/plugins/room.wasm"; do
        if [ -e "$_f" ] && [ ! -L "$_f" ]; then
          rm -f "$_f"
        fi
      done
    '';

    # room — floating fuzzy TAB switcher (C-o w). Tabs are the tmux-window
    # analog here; tmux muscle memory says w = choose-window, s = sessions.
    home.file.".config/zellij/plugins/room.wasm".source = pkgs.fetchurl {
      url = "https://github.com/rvcas/room/releases/download/v1.2.0/room.wasm";
      sha256 = "0k5fy3svjvifsgp0kdvqdx9m9rzrql9cwq6hbvxdgklfnczqz8dp";
    };

    home.activation.zellijThemeSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      _zj="${config.xdg.configHome}/zellij/themes"
      if [ ! -f "$_zj/ono-sendai.kdl" ]; then
        mkdir -p "$_zj"
        cp ${pkgs.writeText "zellij-ono-sendai-seed.kdl" ''
          // seeded by nix; wintermute owns this file after first reconcile
          themes {
              ono-sendai {
                  fg "${colors.base05}"
                  bg "${colors.base00}"
                  black "${colors.base01}"
                  red "${colors.base08}"
                  green "${colors.base0B}"
                  yellow "${colors.base0A}"
                  blue "${colors.base0D}"
                  magenta "${colors.base0E}"
                  cyan "${colors.base0C}"
                  white "${colors.base07}"
                  orange "${colors.base09}"
              }
          }
        ''} "$_zj/ono-sendai.kdl"
        chmod 644 "$_zj/ono-sendai.kdl"
      fi
    '';

    # fzf + atuin: seed the wintermute-owned color files if absent, so a cold
    # shell (before the daemon has ever reconciled) is already themed. The
    # daemon overwrites both on its first reconcile and owns them after.
    home.activation.fzfThemeSeed = lib.mkIf cfg.cliTools.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _fzf="${config.xdg.stateHome}/wintermute/fzf.opts"
        if [ ! -f "$_fzf" ]; then
          mkdir -p "${config.xdg.stateHome}/wintermute"
          cp ${
            pkgs.writeText "fzf-wintermute-seed.opts"
              "--color=fg:${colors.base05},bg:${colors.base00},hl:${colors.base0A},fg+:${colors.base07},bg+:${colors.base01},hl+:${colors.base0A},info:${colors.base04},border:${colors.base02},prompt:${colors.base0A},pointer:${colors.base0C},marker:${colors.base0B},spinner:${colors.base0C},header:${colors.base04},gutter:${colors.base00}\n"
          } "$_fzf"
          chmod 644 "$_fzf"
        fi
      ''
    );

    home.activation.atuinThemeSeed = lib.mkIf cfg.atuin.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        _at="${config.xdg.configHome}/atuin/themes"
        if [ ! -f "$_at/wintermute.toml" ]; then
          mkdir -p "$_at"
          cp ${
            pkgs.writeText "atuin-wintermute-seed.toml" ''
              # seeded by nix; wintermute owns this file after first reconcile
              [theme]
              name = "wintermute"

              [colors]
              Base = "${colors.base05}"
              Title = "${colors.base0A}"
              Guidance = "${colors.base04}"
              Important = "${colors.base07}"
              Annotation = "${colors.base03}"
              AlertInfo = "${colors.base0B}"
              AlertWarn = "${colors.base0A}"
              AlertError = "${colors.base08}"
              Muted = "${colors.base04}"
            ''
          } "$_at/wintermute.toml"
          chmod 644 "$_at/wintermute.toml"
        fi
      ''
    );

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

        # n.b. do NOT add the `sync` terminal-feature (DECSET 2026 redraw
        # bracketing). It cures linewise tearing from bursty remote TUIs, but
        # with tmux 3.7 + ghostty 1.3 the brackets throttle throughput to a
        # crawl under heavy output and choose-tree redraws arrive with an
        # unclosed bracket — ghostty withholds the frame and the view goes
        # blank. Revisit when the pairing handles 2026 under load; tearing
        # over ssh is better addressed with mosh or local-emacs-over-TRAMP.

        # Ensure SSH_TTY is updated in new windows
        set -ag update-environment "SSH_TTY"

        # ── Cursor: single-writer discipline ───────────────────────────────────
        # DECSCUSR (`CSI Ps SP q`) is last-writer-wins, and every sequence the
        # outer terminal receives restarts its blink timer — so exactly one
        # layer may speak at a time. The contract across the stack:
        #
        #   idle shell → terminal config rules (ghostty/wezterm: blinking
        #                block), because nothing else speaks
        #   neovim     → asserts its style via guicursor; tmux passes it
        #                through via the Ss/Se capabilities below (the
        #                tmux-256color terminfo lacks them, so without these
        #                overrides tmux eats the escapes)
        #   tmux       → stays silent. do NOT set `cursor-style`: it makes tmux
        #                re-assert the style on every redraw, flapping between
        #                blinking and steady block (measured: 11 DECSCUSR
        #                writes in 8s of light output) — each write resets the
        #                outer blink timer, which reads as stutter
        #
        # n.b. the xterm-256color line covers wezterm (its default TERM).
        set -ga terminal-overrides ',xterm-ghostty:Ss=\E[%p1%d q:Se=\E[ q'
        set -ga terminal-overrides ',ghostty:Ss=\E[%p1%d q:Se=\E[ q'
        set -ga terminal-overrides ',xterm-256color:Ss=\E[%p1%d q:Se=\E[ q'

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

    # fzf reads $FZF_DEFAULT_OPTS_FILE on every launch, so wintermute rewriting
    # that file (on each reconcile) retints the next fzf with no shell reload —
    # the live channel the old env-baked FZF_DEFAULT_OPTS could never be.
    home.sessionVariables = lib.mkIf cfg.cliTools.enable {
      FZF_DEFAULT_OPTS_FILE = "${config.xdg.stateHome}/wintermute/fzf.opts";
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
    home.packages = [ pkgs.zellij ] ++ lib.optionals cfg.cliTools.enable (
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
