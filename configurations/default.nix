# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // hypermodern // nix // configurations
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The flake-parts module that wires the whole fleet. Replaces nixos-unified:
#
#   - flake.nixosModules / homeModules / overlays  (was autoWire)
#   - flake.nixosConfigurations                    (was autoWire + mkLinuxSystem)
#   - legacyPackages.homeConfigurations            (was autoWire + mkHomeConfiguration)
#   - specialArgs = { flake = { self; inputs; config; }; }  (the {flake,...} every
#     host/home module destructures — preserved verbatim for compatibility)
#
# Adding a NixOS host = one entry in `hosts` + a configurations/nixos/<name>/.
# Adding a standalone home user = one configurations/home/<name>.nix (auto-found).
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{
  self,
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (inputs) nixpkgs home-manager;

  # The argument every module destructures as `{ flake, ... }`, providing
  # flake.inputs / flake.self / flake.config. Identical to nixos-unified's
  # specialArgsFor.nixos so existing configs need no changes.
  specialArgs = {
    flake = { inherit self inputs config; };
  };

  # home-manager-as-a-NixOS-module wiring, matching the previous nixos-unified
  # behaviour: useGlobalPkgs + useUserPackages + extraSpecialArgs. We do NOT put
  # homeModules.default in sharedModules — that would force the full home config
  # onto every HM user (e.g. test-vm's inline `test` user, which lacks the home
  # agenix module). Managed users get homeModules.default via the identity module
  # (modules/flake/registry/nixos-users.nix), which imports
  # configurations/home/<name>.nix per registry user when the file exists.
  homeManagerNixosModule = {

    imports = [
      home-manager.nixosModules.home-manager
    ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = specialArgs;
    };
  };

  # The fleet. system defaults to x86_64-linux; shimmer/gossamer are the aarch64 DGX Sparks.
  hosts = {
    gossamer.system = "aarch64-linux";
    shimmer.system = "aarch64-linux";

    guccimane = { };
    shannon = { };
    test-vm = { };
    ultraviolence = { };
    watchtower = { };
    weyl = { };
  };

  mkHost =
    name:
    {
      system ? "x86_64-linux",
    }:
    nixpkgs.lib.nixosSystem {
      inherit specialArgs;
      modules = [
        { nixpkgs.hostPlatform = system; }
        homeManagerNixosModule
        ./nixos/${name}/default.nix
      ];
    };

  # Standalone home configs (configurations/home/<user>.nix) for `nh home switch`.
  homeUsers = lib.pipe (builtins.readDir ./home) [
    (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n))
    (lib.mapAttrs' (n: _: lib.nameValuePair (lib.removeSuffix ".nix" n) (./home + "/${n}")))
  ];
in
{
  flake = {
    nixosModules = {
      default = ../modules/nixos;
      dgx-spark = ../modules/nixos/dgx-spark;
      wayland = ../modules/nixos/wayland;
    };

    homeModules.default = ../modules/home;

    nixosConfigurations = lib.mapAttrs mkHost hosts;
  };

  perSystem = { pkgs, ... }: {
    legacyPackages.homeConfigurations = lib.mapAttrs (
      _: mod:
      home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = specialArgs;
        modules = [ mod ];
      }
    ) homeUsers;
  };
}
