# Home-manager impermanence integration
#
# This module provides user-level persistence configuration.
# The impermanence home-manager module must be imported at the configuration level
# (in configurations/home/*.nix) to provide the home.persistence option.
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.hyper-modern-nixos.impermanence;
in
{
  options.hyper-modern-nixos.impermanence = {
    enable = lib.mkEnableOption "home-manager impermanence - persist user state";

    persistPath = lib.mkOption {
      type = lib.types.str;
      default = "/persist/home";
      description = "Path to persistent home storage";
    };

    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # Core user data
        "Documents"
        "Downloads"
        "Music"
        "Pictures"
        "Videos"
        "src"

        # Security/auth
        ".gnupg"
        ".ssh"
        ".password-store"

        # Shell history and state
        ".local/share/atuin"
        ".local/share/direnv"
        ".local/share/zoxide"

        # Editor state
        ".local/state/nvim"
        ".emacs.d"
        ".config/emacs"
        ".cache/emacs"
        ".config/Code"
        ".vscode"

        # Development tools
        ".config/gh"
        ".cargo"
        ".rustup"
        ".cache/uv"
        ".local/share/uv"

        # Desktop state
        ".local/state/wireplumber"
        ".config/discord"
        ".config/spotify"
        ".mozilla"
        ".config/chromium"
        ".config/BraveSoftware"

        # Misc caches worth preserving
        ".cache/nix"
        ".cache/fontconfig"
      ];
      description = "User directories to persist";
    };

    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        ".bash_history"
        ".zsh_history"
      ];
      description = "User files to persist";
    };

    allowOther = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Allow other users to access bind mounts (requires user_allow_other in /etc/fuse.conf)";
    };
  };

  config = lib.mkIf cfg.enable {
    home.persistence."${cfg.persistPath}/${config.home.username}" = {
      directories = cfg.directories;
      files = cfg.files;
      allowOther = cfg.allowOther;
    };
  };
}
