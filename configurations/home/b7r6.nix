{ flake, lib, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    inputs.agenix.homeManagerModules.default
    inputs.impurity.nixosModules.default

    self.homeModules.default
  ];

  # Standalone `nh home switch` has no NixOS host context, so it still needs a
  # monitor layout. Pull the default host's layout from the single source of
  # truth (lib/monitors.nix) at mkDefault priority: when this same config is
  # evaluated INSIDE a NixOS host (via the identity module), that host's
  # configuration.nix sets the same option at normal priority and wins cleanly
  # — so there is no conflicting-definition error (e.g. shimmer vs ultraviolence).
  hyper-modern-nixos.hyprland.monitors =
    let
      monitors = import ../../lib/monitors.nix;
    in
    lib.mkDefault monitors.${monitors.defaultHost};

  # impurity.nix - set configRoot, enable via -impure variant
  # impurity.configRoot = self;

  me = {
    username = "b7r6";
    fullname = "b7r6";
    email = "b7r6@b7r6.net";
  };

  # TODO[b7r6]: this probably belongs in a central place
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  home.stateVersion = "25.05";
}
