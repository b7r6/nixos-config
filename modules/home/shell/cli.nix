{ config, pkgs, ... }:
let
  colors = config.themes.palette;
in
{
  programs.bat = {
    enable = true;

    config = {
      italic-text = "never";
      style = "plain";
    };
  };

  programs.eza = {
    enable = true;

    enableBashIntegration = true;
    enableZshIntegration = true;

    extraOptions = [
      "--color=always"
      "--group-directories-first"
      "--icons"
    ];
  };

  programs.fzf = {
    enable = true;

    enableBashIntegration = true;
    enableZshIntegration = true;

    colors = {
      "bg+" = colors.base01;
      fg = colors.base04;
      "fg+" = colors.base06;
      hl = colors.base0D;
      "hl+" = colors.base0D;
      info = colors.base0A;
      marker = colors.base0C;
      pointer = colors.base0C;
      prompt = colors.base0A;
      spinner = colors.base0C;
    };
  };

  programs.zoxide = {
    enable = true;

    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;

    enableBashIntegration = true;
    enableZshIntegration = true;

    nix-direnv.enable = true;

    config.global = {
      hide_env_diff = true;
    };
  };

  programs.starship = {
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

  home.packages = with pkgs; [
    bat
    btop
    direnv
    duf
    dust
    eza
    fd
    git
    glow
    htop
    jq
    neovim
    ripgrep
    viddy
    vivid
    zoxide
  ];
}
