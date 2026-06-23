# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                          // hyper-modern-nixos // state-audit
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Defensive validator for the fleet's state classification: a compiled GHC-9.12
# program that checks the invariants which, if violated, cause silent data loss
# (path not backed up, path wiped on reboot, path excluded by a glob).
{ haskell }:
let
  hp = haskell.packages.ghc912;
in
hp.callCabal2nix "state-audit" ./. { }
