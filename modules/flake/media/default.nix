# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                      // hyper-modern-nixos // flake // media
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-contained flake-parts module for the media subsystem.
#
# Owns:
#   - NixOS modules: media servers (./nixos.nix), dropbox (./nixos-dropbox.nix),
#     pinchflat (./nixos-pinchflat.nix), torrents (./nixos-torrents.nix)
#   - packages: drop CLI (./packages/drop/), pinchflat OCI image (./packages/pinchflat-image/)
_: {
  flake.nixosModules.media = ./nixos.nix;
  flake.nixosModules.media-dropbox = ./nixos-dropbox.nix;
  flake.nixosModules.media-pinchflat = ./nixos-pinchflat.nix;
  flake.nixosModules.media-torrents = ./nixos-torrents.nix;
}
