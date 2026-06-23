# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                 // hyper-modern-nixos // flake // nativelink
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-contained flake-parts module for NativeLink remote execution.
#
# Owns:
#   - the NixOS module (./nixos.nix) — `hyper-modern-nixos.nativelink`
#   - the typed Dhall fleet config (./data/) — rendered at eval via IFD
#   - the VM test (./checks/serve.nix)
{ inputs, ... }: {
  flake.nixosModules.nativelink = ./nixos.nix;

  perSystem = { pkgs, system, ... }: {
    checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      nativelink = import ./checks/serve.nix { inherit pkgs inputs; };
    };
  };
}
