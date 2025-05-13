# Weyl configuration - pure Wayland with minimal dependencies
{
  flake,
  pkgs,
  lib,
  ...
}:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    ./configuration.nix
  ];

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  # Configure pure Wayland Hyprland for Weyl
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    # No XWayland by default - only enable if someone specifically needs it
    xwayland.enable = false;
  };

  # NVIDIA optimizations for this specific hardware
  environment.variables = {
    # NVIDIA optimizations
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  # Add developer tools
  environment.systemPackages = with flake.inputs.nixpkgs.legacyPackages.x86_64-linux; [
    bat
    btop
    fd
    fzf
    git-lfs
    gitui
    jq
    lf
    tree
    tmux
    vim
    wget
  ];
}
