{ config, lib, ... }:
with lib;
let
  cfg = config.programs.themed-shell;
  colors = config.themes.palette;
in
{
  options.programs.themed-shell = {
    enable = lib.mkEnableOption "Themed shell with starship and atuin";
  };

  config = mkIf cfg.enable {
    programs.starship = {
      enable = true;
      settings = {
        format = "$username$hostname$directory$git_branch$git_state$git_status$cmd_duration$line_break$python$character";

        directory = {
          style = colors.base0D; # blue
        };

        character = {
          success_symbol = "[❯](${colors.base0E})"; # purple
          error_symbol = "[❯](${colors.base08})"; # red
          vimcmd_symbol = "[❮](${colors.base0B})"; # green
        };

        git_branch = {
          format = "[$branch]($style)";
          style = colors.base03; # bright-black
        };

        git_status = {
          format = "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
          style = colors.base0C; # cyan
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
          style = colors.base03; # bright-black
        };

        cmd_duration = {
          format = "[$duration]($style) ";
          style = colors.base0A; # yellow
        };

        python = {
          format = "[$virtualenv]($style) ";
          style = colors.base03; # bright-black
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

        theme = {
          Base = colors.base05;
          Title = colors.base0D;
          Important = colors.base0E;
          Annotation = colors.base03;
          Guidance = colors.base0C;
          AlertInfo = colors.base0B;
          AlertWarn = colors.base0A;
          AlertError = colors.base08;
        };
      };
    };
  };
}
