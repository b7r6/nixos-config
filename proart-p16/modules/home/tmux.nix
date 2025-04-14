# tmux configuration for ProArt P16
{ config, lib, pkgs, ... }:

{
  options.programs.tmux-config = {
    enable = lib.mkEnableOption "Enable tmux with custom configuration";
  };

  config = lib.mkIf config.programs.tmux-config.enable {
    programs.tmux = {
      enable = true;
      
      # Use 256 colors
      terminal = "tmux-256color";
      
      # Enable mouse support
      mouse = true;
      
      # Set prefix to Ctrl+a (more ergonomic than Ctrl+b)
      prefix = "C-a";
      
      # Start windows and panes at 1, not 0
      baseIndex = 1;
      
      # Increase scrollback buffer
      historyLimit = 10000;
      
      # Automatically renumber windows when one is closed
      secureSocket = true;
      
      # Wait only 10ms after escape to determine if it's part of a function or meta key sequence
      escapeTime = 10;
      
      # Focus events for Vim, etc.
      focusEvents = true;
      
      # Resize aggressively based on client size
      aggressiveResize = true;
      
      # Set XTerm key bindings (for better key compatibility)
      keyMode = "vi";
      
      # Custom shortcuts and settings
      extraConfig = ''
        # Improve colors
        set -g default-terminal "tmux-256color"
        set -ga terminal-overrides ",*256col*:Tc"
        
        # Status bar design
        set -g status-style 'bg=colour236 fg=colour15'
        set -g status-left-length 40
        set -g status-left "#[fg=colour15,bg=colour33,bold] #S #[fg=colour33,bg=colour236,nobold]"
        set -g status-right "#[fg=colour10,bg=colour236] %d-%b-%Y #[fg=colour10,bg=colour236] %H:%M "
        set -g status-justify centre
        
        # Window status
        setw -g window-status-format " #I:#W "
        setw -g window-status-current-format "#[fg=colour236,bg=colour33]#[fg=colour15,bg=colour33,bold] #I:#W #[fg=colour33,bg=colour236,nobold]"
        
        # Pane borders
        set -g pane-border-style 'fg=colour238'
        set -g pane-active-border-style 'fg=colour33'
        
        # Pane navigation with vim-like bindings
        bind-key h select-pane -L
        bind-key j select-pane -D
        bind-key k select-pane -U
        bind-key l select-pane -R
        
        # Window splitting
        bind-key v split-window -h -c "#{pane_current_path}"
        bind-key s split-window -v -c "#{pane_current_path}"
        
        # New window with current path
        bind-key c new-window -c "#{pane_current_path}"
        
        # Fast toggling between current and last window
        bind-key a last-window
        
        # Reorder windows
        bind-key -n M-Left swap-window -t -1\; select-window -t -1
        bind-key -n M-Right swap-window -t +1\; select-window -t +1
        
        # Copy mode
        bind-key [ copy-mode
        bind-key -T copy-mode-vi v send -X begin-selection
        bind-key -T copy-mode-vi y send -X copy-selection-and-cancel
        
        # Reload configuration
        bind-key r source-file ~/.config/tmux/tmux.conf \; display-message "Config reloaded!"
        
        # Session management
        bind-key S choose-session
        
        # Synchronize panes (send command to all panes)
        bind-key y setw synchronize-panes
        
        # Smart session integration with resurrecting features
        set -g @continuum-restore 'on'
        set -g @resurrect-strategy-nvim 'session'
      '';
      
      # Include useful plugins
      plugins = with pkgs.tmuxPlugins; [
        sensible       # Sensible defaults
        yank           # Better copy/paste
        resurrect      # Save/restore sessions
        continuum      # Auto-save sessions
        vim-tmux-navigator  # Seamless navigation between vim and tmux
        {
          plugin = dracula;
          extraConfig = ''
            set -g @dracula-show-battery false
            set -g @dracula-show-powerline true
            set -g @dracula-refresh-rate 10
            set -g @dracula-show-weather false
            set -g @dracula-show-fahrenheit false
            set -g @dracula-show-location false
            set -g @dracula-border-contrast true
            set -g @dracula-show-left-icon session
          '';
        }
      ];
    };
    
    # Additional utilities related to tmux
    home.packages = with pkgs; [
      tmux-mem-cpu-load  # System stats in status bar
      fzf                # Fuzzy finder integration
      tmuxinator         # Session manager
    ];
    
    # Script to create standard dev session layout
    home.file.".local/bin/tmux-dev" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        
        # Check if session exists, create if not
        SESSION_NAME="dev"
        if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
          # Create new session
          tmux new-session -d -s "$SESSION_NAME" -c "$HOME"
          
          # Window 1: Editor + Terminal
          tmux rename-window -t "$SESSION_NAME:1" "editor"
          tmux split-window -h -t "$SESSION_NAME:1" -c "#{pane_current_path}"
          tmux select-pane -t "$SESSION_NAME:1.1"
          tmux send-keys -t "$SESSION_NAME:1.1" "nvim" C-m
          
          # Window 2: Terminal
          tmux new-window -t "$SESSION_NAME" -c "#{pane_current_path}" -n "terminal"
          
          # Window 3: Monitoring
          tmux new-window -t "$SESSION_NAME" -c "#{pane_current_path}" -n "monitor"
          tmux send-keys -t "$SESSION_NAME:3" "btop" C-m
          
          # Select first window
          tmux select-window -t "$SESSION_NAME:1"
        fi
        
        # Attach to session
        if [ -z "$TMUX" ]; then
          tmux attach-session -t "$SESSION_NAME"
        else
          tmux switch-client -t "$SESSION_NAME"
        fi
      '';
    };
  };
} 