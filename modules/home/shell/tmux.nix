{ config, ... }:
let
  colors = config.themes.palette;
in
{
  programs.tmux = {
    enable = true;
    prefix = "C-o";

    # conservative and widely supported terminal type
    terminal = "tmux-256color";
    escapeTime = 10;
    historyLimit = 10000;
    keyMode = "emacs";
    baseIndex = 1;
    mouse = true;
    clock24 = true;

    # explicitly disable any potentially problematic features
    sensibleOnTop = false; # Prevent sensible plugin from overriding our careful settings

    extraConfig = ''
      # well-supported terminal type that works virtually everywhere
      set -g default-terminal "tmux-256color"

      # only set RGB capability for terminals we're confident support it correctly
      set -ga terminal-overrides ",xterm-256color:Tc"
      set -ga terminal-overrides ",alacritty:RGB"
      set -ga terminal-overrides ",wezterm:RGB"
      set -ga terminal-overrides ",ghostty:RGB"

      # Ensure SSH_TTY is updated in new windows
      set -ag update-environment "SSH_TTY"

      # Enable passthrough for escape sequences tmux doesn't understand
      set -g allow-passthrough on

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
}
