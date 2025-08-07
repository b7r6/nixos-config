{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.vscode;
in
{
  options.hyper-modern-nixos.vscode = {
    enable = mkEnableOption "Visual Studio Code configuration" // {
      default = false;
    };

    package = mkOption {
      type = types.package;
      default = pkgs.vscode-fhs;
      description = "VSCode package to use";
      example = "pkgs.vscodium";
    };

    font = {
      family = mkOption {
        type = types.str;
        default = "Berkeley Mono";
        description = "Font family for VSCode editor";
      };

      size = mkOption {
        type = types.int;
        default = 14;
        description = "Font size for VSCode editor";
      };
    };

    extensions = {
      enable = mkEnableOption "install recommended extensions" // {
        default = true;
      };

      extra = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Additional VSCode extensions to install";
        example = literalExpression "[ pkgs.vscode-extensions.ms-python.python ]";
      };
    };

    settings = mkOption {
      type = types.attrs;
      default = { };
      description = "Additional VSCode user settings";
      example = literalExpression ''
        {
          "editor.tabSize" = 2;
          "editor.insertSpaces" = true;
        }
      '';
    };

    profiles = mkOption {
      type = types.attrsOf types.attrs;
      default = { };
      description = "VSCode profiles configuration";
      example = literalExpression ''
        {
          "typescript-dev" = {
            extensions = [ typescript-specific-extensions ];
            settings = { "typescript.preferences.importModuleSpecifier" = "relative"; };
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    programs.vscode = {
      enable = true;
      inherit (cfg) package;

      profiles = {
        default = {
          extensions = mkIf cfg.extensions.enable (
            (with pkgs.vscode-extensions; [
              ionide.ionide-fsharp
              jnoortheen.nix-ide
              ms-dotnettools.csdevkit
              ms-dotnettools.csharp
              ms-dotnettools.vscodeintellicode-csharp
              ms-pyright.pyright
              ms-python.debugpy
              ms-python.python
              ms-python.vscode-pylance
            ])
            ++ (pkgs.vscode-utils.extensionsFromVscodeMarketplace [
              {
                name = "vscode-openapi";
                publisher = "42crunch";
                version = "4.32.2";
                hash = "sha256-A8I2BmW5CFYkEFOpMqsGaKUomiLdOdBSKz+bunW/UQo=";
              }
              {
                name = "vscode-emacs-friendly";
                publisher = "lfs";
                version = "0.9.0";
                hash = "sha256-YWu2a5hz0qGZvgR95DbzUw6PUvz17i1o4+eAUM/xjMg=";
              }
              {
                name = "dotnet-core-commands";
                publisher = "matijarmk";
                version = "1.0.6";
                hash = "sha256-6dRTWnn6FKmA6T2/FrSl//SdfyO4vuiQaBXkZrRjd8Y=";
              }
              {
                name = "vscode-dotnet-runtime";
                publisher = "ms-dotnettools";
                version = "2.3.0";
                hash = "sha256-KfWQpg+qSxrmL4z05pk239i8bY6EMJpu6F48mJbnK08=";
              }
            ])
            ++ cfg.extensions.extra
          );

          userSettings = {
            "nix.enableLanguageServer" = true;
            "nix.serverPath" = "nixd";

            # Font configuration using module options
            "chat.editor.fontFamily" = lib.mkForce cfg.font.family;
            "chat.editor.fontSize" = lib.mkForce cfg.font.size;
            "debug.console.fontFamily" = lib.mkForce cfg.font.family;
            "debug.console.fontSize" = lib.mkForce cfg.font.size;
            "editor.fontFamily" = lib.mkForce cfg.font.family;
            "editor.fontSize" = lib.mkForce cfg.font.size;
            "editor.inlayHints.fontFamily" = lib.mkForce cfg.font.family;
            "editor.inlineSuggest.fontFamily" = lib.mkForce cfg.font.family;
            "editor.minimap.sectionHeaderFontSize" = lib.mkForce cfg.font.size;
            "markdown.preview.fontFamily" = lib.mkForce cfg.font.family;
            "markdown.preview.fontSize" = lib.mkForce cfg.font.size;
            "scm.inputFontFamily" = lib.mkForce cfg.font.family;
            "scm.inputFontSize" = lib.mkForce cfg.font.size;
            "terminal.integrated.fontSize" = lib.mkForce cfg.font.size;
          } // cfg.settings;
        };
      } // cfg.profiles;
    };

    # Additional packages
    home.packages = with pkgs; [ code-cursor ];
  };
}
