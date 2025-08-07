{ config, lib, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.dev;
in
{
  options.hyper-modern-nixos.dev = {
    enable = mkEnableOption "development toolchain" // {
      default = true;
    };

    git = {
      enable = mkEnableOption "git configuration" // {
        default = true;
      };

      userName = mkOption {
        type = types.str;
        default = config.me.username or "user";
        description = "Git user name";
      };

      userEmail = mkOption {
        type = types.str;
        default = config.me.email or "user@example.com";
        description = "Git user email";
      };

      aliases = mkOption {
        type = types.attrsOf types.str;
        default = {
          st = "status";
          ci = "commit";
          co = "checkout";
          br = "branch";
          unstage = "reset HEAD --";
          last = "log -1 HEAD";
          lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";
        };
        description = "Git aliases to configure";
      };

      extraConfig = mkOption {
        type = types.attrs;
        default = { };
        description = "Additional git configuration";
        example = literalExpression ''
          {
            push.autoSetupRemote = true;
            pull.rebase = true;
          }
        '';
      };
    };

    languages = {
      python = mkEnableOption "Python development tools" // {
        default = true;
      };

      typescript = mkEnableOption "TypeScript/JavaScript development tools" // {
        default = true;
      };

      ruby = mkEnableOption "Ruby development tools" // {
        default = false;
      };

      shell = mkEnableOption "Shell scripting tools" // {
        default = true;
      };

      systems = mkEnableOption "Systems development tools" // {
        default = true;
      };

      dotnet = mkEnableOption ".NET development tools" // {
        default = false;
      };
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Additional development packages to install";
    };
  };

  imports = [
    ./development.nix
    ./git.nix
    ./python-development.nix
    ./ruby-development.nix
    ./shell-development.nix
    ./systems-development.nix
    ./typescript-development.nix
  ];

  config = mkIf cfg.enable {
    # Git configuration
    programs.git = mkIf cfg.git.enable {
      enable = true;
      inherit (cfg.git) userName;
      inherit (cfg.git) userEmail;
      inherit (cfg.git) aliases;
      extraConfig = {
        init.defaultBranch = "main";
        pull.rebase = true;
        rebase.autoStash = true;
        fetch.prune = true;
        push.autoSetupRemote = true;
        diff.colorMoved = "default";
      } // cfg.git.extraConfig;

      ignores = [
        ".DS_Store"
        "*.swp"
        ".direnv/"
        ".envrc"
        "result"
        "result-*"
      ];
    };

    home.packages = cfg.extraPackages;
  };
}
