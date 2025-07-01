{ pkgs, lib, ... }:
{
  stylix.targets.vscode.enable = true;
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
          name = "vscode-openapi";
          publisher = "42crunch";
          version = "4.32.2";
          hash = "sha256-A8I2BmW5CFYkEFOpMqsGaKUomiLdOdBSKz+bunW/UQo=";
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

      "chat.editor.fontFamily" = lib.mkForce "Berkeley Mono";
      "chat.editor.fontSize" = lib.mkForce 14;
      "debug.console.fontFamily" = lib.mkForce "Berkeley Mono";
      "debug.console.fontSize" = lib.mkForce 14;
      "editor.fontFamily" = lib.mkForce "Berkeley Mono";
      "editor.fontSize" = lib.mkForce 14;
      "editor.inlayHints.fontFamily" = lib.mkForce "Berkeley Mono";
      "editor.inlineSuggest.fontFamily" = lib.mkForce "Berkeley Mono";
      "editor.minimap.sectionHeaderFontSize" = lib.mkForce 14;
      "markdown.preview.fontFamily" = lib.mkForce "Berkeley Mono";
      "markdown.preview.fontSize" = lib.mkForce 14;
      "scm.inputFontFamily" = lib.mkForce "Berkeley Mono";
      "scm.inputFontSize" = lib.mkForce 14;
      "terminal.integrated.fontSize" = lib.mkForce 14;
    };
  };

  # TODO[b7r6]: re-do the extensiosn and settings...
  home.packages = with pkgs; [ code-cursor ];
}
