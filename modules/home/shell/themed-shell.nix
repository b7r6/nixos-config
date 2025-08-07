{ config, lib, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.themed-shell;
in
{
  options.hyper-modern-nixos.themed-shell = {
    enable = lib.mkEnableOption "Themed shell with starship and atuin";

    starship = {
      format = mkOption {
        type = types.str;
        default = "$username$hostname$directory$git_branch$git_state$git_status$cmd_duration$line_break$python$character";
        description = "Starship prompt format string";
      };
    };

    atuin = {
      syncAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Atuin sync server address";
      };

      keyPath = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to atuin encryption key";
      };

      settings = mkOption {
        type = types.attrs;
        default = { };
        description = "Additional atuin settings";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.starship = {
      enable = true;
      settings = {
        inherit (cfg.starship) format;

        character = {
          # success_symbol = "[❯]";
          # error_symbol = "[❯]";
          # vimcmd_symbol = "[❮]";
        };

        git_branch = {
          format = "[$branch]($style)";
        };

        git_status = {
          format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
          conflicted = "​";
          untracked = "​";
          modified = "​";
          staged = "​";
          renamed = "​";
          deleted = "​";
          stashed = "≡";
        };

        git_state = {
          format = "\\([$state( $progress_current/$progress_total)]($style)\\) ";
        };

        cmd_duration = {
          format = "[$duration]($style) ";
        };

        python = {
          format = "[$virtualenv]($style) ";
        };
      };
    };

    programs.atuin = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;

      settings =
        {
          update_check = false;
          dialect = "us";
          style = "auto";
        }
        // (optionalAttrs (cfg.atuin.syncAddress != null) { sync_address = cfg.atuin.syncAddress; })
        // (optionalAttrs (cfg.atuin.keyPath != null) { key_path = cfg.atuin.keyPath; })
        // (optionalAttrs (cfg.atuin.settings != { }) cfg.atuin.settings);
    };
  };
}
