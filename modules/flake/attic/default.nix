# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                     // hyper-modern-nixos // flake // attic
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-contained flake-parts module for attic binary cache.
#
# Owns:
#   - the NixOS modules (./nixos.nix, ./nixos-node.nix)
#   - the VM test (./checks/cache.nix)
{ inputs, ... }: {
  flake.nixosModules.attic = ./nixos.nix;
  flake.nixosModules.attic-node = ./nixos-node.nix;

  perSystem = { pkgs, system, ... }: {
    checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      attic-cache = import ./checks/cache.nix { inherit pkgs inputs; };
    };
  };
}
