# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // flake // coredns
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-contained flake-parts module for fleet DNS (CoreDNS).
#
# Owns:
#   - the NixOS module (./nixos.nix) — `hyper-modern-nixos.coredns`
#   - the VM test (./checks/dns.nix)
{ inputs, ... }:
{
  flake.nixosModules.coredns = ./nixos.nix;

  perSystem = { pkgs, system, ... }: {
    checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      coredns = import ./checks/dns.nix { inherit pkgs inputs; };
    };
  };
}
