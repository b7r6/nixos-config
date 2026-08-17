# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // hyper-modern-nixos // eyes-still
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# One frame of the EYES card, rendered at build time by the kernel's CPU
# path — the SAME __host__ __device__ function the live GPU wallpaper runs,
# bit-comparable by the conformance gate. For the surfaces that can't host
# the daemon: the SDDM greeter, the swaylock lock screen. The CLI's default
# palette is carbon night, matching the greeter's build-time palette.
{
  pkgs,
  flake,
  width ? 3840,
  height ? 2160,
  time ? 2.0,
}:
let
  wintermuteField = pkgs.callPackage "${flake.inputs.straylight-nvidia-sdk}/examples/wintermute-field" {
    cuda = flake.inputs.straylight-nvidia-sdk.packages.${pkgs.stdenv.hostPlatform.system}.cuda;
  };
in
pkgs.runCommand "eyes-still-${toString width}x${toString height}"
  {
    nativeBuildInputs = [ pkgs.imagemagick ];
  }
  ''
    ${wintermuteField}/bin/wintermute-field --cpu --scene eyes \
      --size ${toString width}x${toString height} \
      --time ${toString time} --load 0.35 \
      --out frame.ppm
    mkdir -p $out
    magick frame.ppm $out/eyes.png
  ''
