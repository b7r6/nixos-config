{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.vscode;
in
{
  options.hyper-modern-nixos.vscode = {
    enable = lib.mkEnableOption "VS Code editor configuration";

    cursor.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Cursor (VS Code fork with AI)";
    };

    stylix.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Stylix theme integration for VS Code";
    };

    font = {
      family = lib.mkOption {
        type = lib.types.str;
        default = "Berkeley Mono";
        description = "Font family for VS Code";
      };

      size = lib.mkOption {
        type = lib.types.int;
        default = 14;
        description = "Font size for VS Code";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    stylix.targets.vscode.enable = cfg.stylix.enable;
    stylix.targets.vscode.profileNames = [ "default" ];

    programs.vscode = {
      enable = true;
      package = pkgs.vscode-fhs;

      profiles.default.extensions =
        with pkgs.vscode-extensions;
        [
          ionide.ionide-fsharp
          jnoortheen.nix-ide
          ms-dotnettools.csdevkit
          ms-dotnettools.csharp
          ms-dotnettools.vscodeintellicode-csharp
          ms-pyright.pyright
          ms-python.debugpy
          ms-python.python
          ms-python.vscode-pylance
        ]
        ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
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
        ];

      profiles.default.userSettings = {
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";

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
      };
    };

    home.packages = lib.mkIf cfg.cursor.enable [ pkgs.code-cursor ];
  };
}
