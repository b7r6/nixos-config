{ config, pkgs,... }:
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

  home.packages = with pkgs; [
    wemux
  ];

  # home.file.".wemux.conf".text = ''
  #   ## wemux Configuration:
  #   ## wemux version 3.2.0
  #   ##
  #   ## Uncomment an option (remove the # in front of it) if you would like to change
  #   ## the option from its default setting.

  #   ####### HOST OPTIONS #######

  #   ## All usernames in host_list will use wemux in host mode, allowing
  #   ## them to create wemux servers for other users to attach to.
  #   ## Add the usernames of users who should use wemux in host mode:
  #   host_list=(b7r6 gedanziger)
    
  #   ## All users in any of the groups in host_groups will also use wemux in host mode.
  #   ## example: host_groups=(wheel wemux)
    
  #   ####### CLIENT OPTIONS #######
    
  #   ## Allow users to attach to the wemux server in pair mode.
  #   ## When set to false, clients will only be able to attach in mirror mode.
  #   ## Defaults to "true"
  #   # allow_pair_mode="false"
    
  #   ## Allow users to attach to the wemux server in rogue mode.
  #   ## When set to false, clients will only be able to attach in pair or mirror mode.
  #   ## Defaults to "true"
  #   # allow_rogue_mode="false"
    
  #   ## When clients enter 'wemux' with no arguments by default it will attempt to
  #   ## join an existing pair mode session, if there is no pair session it will start
  #   ## a mirror mode session.
  #   ## By setting default_client_mode to "pair", 'wemux' with no arguments will always
  #   ## join a pair mode session, even if it has to create it.
  #   ## Defaults to "mirror"
  #   # default_client_mode="pair"
    
  #   ## Allow hosts to kick SSH users from the server and remove the kicked users
  #   ## wemux sessions.
  #   ## Defaults to "true"
  #   # allow_kick_user="false"
    
  #   ####### MULTI-HOST OPTIONS #######
    
  #   ## Allow users to change their server for multi-host environments.
  #   ## Defaults to "false"
  #   # allow_server_change="true"
    
  #   ## Set name for default wemux server. Will be used with wemux reset and
  #   ## when allow_server_change is disabled.
  #   ## Defaults to "wemux"
  #   # default_server_name="customname"
    
  #   ## Allow users to list all currently running wemux sockets/servers.
  #   ## Automatically disabled if allow_server_change="false"
  #   ## Defaults to "true"
  #   # allow_server_list="false"
    
  #   ####### ANNOUNCEMENT OPTIONS #######
    
  #   ## Allow users to see list of currently connected wemux users.
  #   ## Defaults to "true"
  #   # allow_user_list="false"
    
  #   ## Announce when users attach/detach from a tmux server.
  #   ## Defaults to "true"
  #   # announce_attach="false"
    
  #   ## Announce when users change the wemux server they are using.
  #   ## Defaults to "true"
  #   # announce_server_change="false"
    
  #   ####### OTHER OPTIONS #######
    
  #   ## Location of tmux socket, will have server name appended to end:
  #   ## Defaults to "/tmp/wemux"
  #   # socket_prefix="/tmp/wemux"
    
  #   ## Tmux Options:
  #   ## Defaults to -u to have tmux always attempt to use utf-8 mode.
  #   # options="-u"
  # '';
}
