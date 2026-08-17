# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hypermodern // nix // nativelink
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The NixOS module itself lives in the FORK (the fork owns its ops):
# inputs.nativelink-nix.nixosModules.nativelink. This repo keeps what is OURS:
#   - the typed Dhall fleet topology (./data/) — rendered at eval via IFD
#   - the shim (./shim.nix) wiring fleetDir + telemetry + the state registry
#   - the VM test (./checks/serve.nix)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{ inputs, ... }: {
  flake.nixosModules.nativelink = {
    imports = [
      inputs.nativelink-nix.nixosModules.nativelink
      ./shim.nix
    ];
  };

  perSystem = { pkgs, system, ... }: {
    checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      nativelink = import ./checks/serve.nix { inherit pkgs inputs; };
    };
  };
}
