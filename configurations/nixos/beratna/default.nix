{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    self.nixosModules.gui
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
    xwayland.enable = false;
  };

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
