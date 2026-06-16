# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // flake // overlays
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Surfaces the repo overlay (modules/overlays/default.nix) as the flake output
# `self.overlays.default`. This file lives under modules/flake/ specifically so
# nixos-unified's autoWire imports it into the flake-parts evaluation.
{ flake.overlays.default = import ../overlays/default.nix; }
