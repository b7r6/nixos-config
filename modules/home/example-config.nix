# Example user configuration
# Include this module in your configuration to see how to use module options
_:

# This is a template - copy this file and customize it for your configuration
{
  # -------------------------------------------
  # Required: Configure basic user identity
  # -------------------------------------------
  me = {
    username = "username"; # Replace with your actual username
    fullname = "Your Full Name";
    email = "your.email@example.com";
  };

  # -------------------------------------------
  # Desktop Environment Configuration
  # -------------------------------------------
  wayland = {
    # Control all wayland desktop environments
    enable = true;

    # Configure specific desktop environments
    hyprland.enable = true; # Use Hyprland (default true)
    plasma.enable = false; # Don't use Plasma (default false)
  };

  # -------------------------------------------
  # Development Environment Configuration
  # -------------------------------------------
  dev = {
    # Control all development tools
    enable = true;

    # Configure language-specific settings
    python.enable = true; # Use Python tools
    ruby.enable = false; # Don't use Ruby tools
    typescript.enable = true; # Use TypeScript tools
    systems.enable = true; # Use systems development tools
    git.enable = true; # Configure Git
  };

  # -------------------------------------------
  # Other Module Categories
  # -------------------------------------------
  # Configure cloud tools
  cloud.enable = true;

  # Enable/disable editor configurations
  emacs.enable = true;
  neovim.enable = true;
  vscode.enable = true;

  # Shell and terminal configurations
  shell.enable = true;
  terminal.enable = true;

  # -------------------------------------------
  # Override specific application configurations
  # -------------------------------------------
  programs.git = {
    userName = "Your Name";
    userEmail = "your.email@example.com";

    # Add any other git settings you prefer
    extraConfig = {
      pull.rebase = true;
      init.defaultBranch = "main";
    };
  };

  # Hyprland specific configurations if needed
  wayland.windowManager.hyprland = {
    settings = {
      # Add your hyprland customizations here
    };
  };
}
