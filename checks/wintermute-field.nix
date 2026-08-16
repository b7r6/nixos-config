# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                          // hyper-modern-nixos // checks // wintermute-field
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Builds the CUDA wallpaper field (CLI + zero-copy wayland presenter) from
# the straylight-nvidia-sdk input, exactly as the new-suzuki module consumes
# it. aarch64 only (the DGX Spark fleet, sm_121). Building IS the gate: nvcc
# compiles the whole __host__ __device__ field, the wayland protocol glue
# generates and links. Pixel conformance (--verify) needs a GPU, so it stays
# a runtime check; the closure existing is what CI can promise.
{
  pkgs,
  inputs,
}:
let
  # cudatoolkit is unfree; the perSystem pkgs set doesn't allow that, so the
  # check imports its own view of the same nixpkgs.
  cudaPkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
in
cudaPkgs.callPackage "${inputs.straylight-nvidia-sdk}/examples/wintermute-field" {
  cuda = inputs.straylight-nvidia-sdk.packages.${pkgs.stdenv.hostPlatform.system}.cuda;
}
