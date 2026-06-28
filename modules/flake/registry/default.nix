# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                  // hyper-modern-nixos // flake // registry
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-contained flake-parts module for the fleet topology registry.
#
# Owns:
#   - the NixOS module (./nixos.nix) — `hyper-modern-nixos.topology`
#   - the typed Dhall registry (./data/) — schema + hosts.dhall (single source
#     of truth; rendered at eval time via IFD, no committed JSON)
#   - the coredns-zone package (./packages/coredns-zone/) — fleet DNS compiler
_: {
  flake.nixosModules.registry = ./nixos.nix;
  flake.nixosModules.identity = ./nixos-users.nix;

  perSystem = { pkgs, ... }: {
    packages.coredns-zone = pkgs.callPackage ./packages/coredns-zone { };
  };
}
