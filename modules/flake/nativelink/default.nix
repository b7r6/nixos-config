# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hypermodern // nix // nativelink
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The NixOS module itself lives in the FORK (the fork owns its ops):
# inputs.nativelink-nix.nixosModules.nativelink. This repo keeps what is OURS:
#   - the typed Dhall fleet topology (./data/) — rendered at eval via IFD
#   - the shim (./shim.nix) wiring fleetDir + telemetry + the state registry
#   - one unit per process for a `split` host (./split.nix)
#   - the VM tests (./checks/serve.nix, ./checks/split.nix)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{ inputs, ... }: {
  flake.nixosModules.nativelink = {
    imports = [
      inputs.nativelink-nix.nixosModules.nativelink
      ./shim.nix
      ./split.nix
    ];
  };

  perSystem = { pkgs, system, ... }: {
    checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      nativelink = import ./checks/serve.nix { inherit pkgs inputs; };
      nativelink-split = import ./checks/split.nix { inherit pkgs inputs; };
    };
  };
}
