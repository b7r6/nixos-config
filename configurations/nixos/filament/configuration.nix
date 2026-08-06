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
{ flake, lib, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    inputs.agenix.nixosModules.default
  ];

  networking.hostName = "filament";

  # Appliance: no home-manager payload. The fleet HM (tracking current
  # nixpkgs) can't evaluate against this host's pinned nixpkgs-jetson
  # (missing lib/services); the box needs no dotfile management anyway.
  home-manager.users = lib.mkForce { };

  # No local nativelink nix cache: its dhall config render fails under the
  # jetson nixpkgs pin, and the box is a cache consumer, not a provider.
  hyper-modern-nixos.nativelink.nixCache.enable = lib.mkForce false;

  # The L4T kernel lacks the conntrack verdict-map support (`ct state vmap`)
  # the fleet nftables ruleset uses; the box lives on LAN+tailnet with the
  # firewall off, same as its pre-migration life.
  networking.nftables.enable = lib.mkForce false;
  networking.firewall.enable = lib.mkForce false;

  hardware.jetson-thor.enable = true;

  # Hardware-specific kernel modules
  boot.initrd.availableKernelModules = [ "nvme" ];

  # The devkit's wifi (rtl8852ce) and bluetooth need blobs from
  # linux-firmware; the jetpack module only ships the L4T set.
  hardware.enableRedistributableFirmware = true;

  # Matches the deployed system (installed as 25.11-era; do not bump on paper)
  system.stateVersion = "25.11";
}
