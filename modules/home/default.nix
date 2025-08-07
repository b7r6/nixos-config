{ pkgs, ... }:
#
# hyper-modern-nixos home-manager configuration
#
# SCOPE: Terminal-first portable experience that works on Ubuntu
#
# This home-manager configuration is designed to provide a complete
# terminal development environment that works across different Linux
# distributions, including Ubuntu. For the full hypermodern desktop
# experience with Wayland/Hyprland, use the NixOS configuration.
#
# Architecture:
# - NixOS: Full system including compositor, fonts, wallpapers, desktop theming
# - Home-Manager: Portable terminal tools, editors, development environment
#
{
  imports = [

    # user identity
    ./me.nix

    # baseline toolchain presets
    ./cloud
    ./dev
    ./llm
    ./nix

    # terminal tooling
    ./emacs
    ./neovim
    ./shell
    ./terminal
    ./themes

    # session management
    ./session

    # optional desktop environments (for systems with GUI)
    ./desktop
    ./vscode
  ];

  hyper-modern-nixos = {
    themes = {
      enable = true;
      theme = "ono-sendai-blue";
      variant = "chiba";
    };

    # Enable VSCode for GUI systems
    vscode.enable = true;

    # Configure shell defaults
    shell = {
      enable = true;
      aesthetic.preset = "matrix";
      tmux.philosophy = "emacs";
      workflow.enableSystemIntegration = true;
    };

    # Configure terminals
    terminals = {
      enable = true;
      font.size = 13;
      aesthetic.cursorProfile = "performance";
      aesthetic.paddingProfile = "comfortable";
    };

    # Configure development tools
    dev = {
      enable = true;
      languages = {
        python = true;
        typescript = true;
        shell = true;
        systems = true;
        ruby = false;
        dotnet = false;
      };
    };
  };

  home.packages = with pkgs; [
    dbus
    dconf
  ];
}
