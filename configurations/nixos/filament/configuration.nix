# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // filament
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# NVIDIA Jetson AGX Thor Developer Kit (T5000) - edge inference / JetPack 7
#
# Re-imaged 2026-08-06 onto the clean disko layout with the host key preserved.
# The netboot/kexec beachhead and full re-image playbook live in
# docs/src/operations/netboot-jetson.md; the platform quirks live in
# modules/nixos/jetson-thor.
#
{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    inputs.agenix.nixosModules.default
  ];

  networking.hostName = "filament";

  hardware.jetson-thor.enable = true;

  # Hardware-specific kernel modules
  boot.initrd.availableKernelModules = [ "nvme" ];

  # Matches the deployed system (installed as 25.11-era; do not bump on paper)
  system.stateVersion = "25.11";
}
