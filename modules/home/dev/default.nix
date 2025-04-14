{ lib, ... }:
{
  options.dev = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable development environments";
    };

    git = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Git configuration";
      };
    };

    dotnet = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Dotnet development environment";
      };
    };

    python = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Python development environment";
      };
    };

    ruby = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Ruby development environment";
      };
    };

    shell = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable shell development tools";
      };
    };

    systems = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable systems development tools";
      };
    };

    typescript = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable TypeScript development environment";
      };
    };
  };

  imports = [
    ./development.nix
    ./git.nix
    # ./dotnet-development.nix
    ./python-development.nix
    ./ruby-development.nix
    ./shell-development.nix
    ./systems-development.nix
    ./typescript-development.nix
  ];
}
