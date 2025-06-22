{ config, lib, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.themed-shell;
in
{
  options.hyper-modern-nixos.themed-shell = {
    enable = lib.mkEnableOption "Themed shell with starship and atuin";
  };

  config = mkIf cfg.enable {
    programs.starship = {
      enable = true;
      settings = {
        format = "$username$hostname$directory$git_branch$git_state$git_status$cmd_duration$line_break$python$character";

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

      settings = {
        update_check = false;
        dialect = "us";
        style = "auto";
      };
    };
  };
}
