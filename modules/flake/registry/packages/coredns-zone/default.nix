# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                         // hyper-modern-nixos // coredns-zone
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The fleet DNS compiler: a real, compiled Haskell (GHC 9.12) program that
# renders the typed Dhall topology registry to a CoreDNS zone. NOT a runghc
# script — DNS is intolerant of silent-wrong output (a bad zone strands the
# network we deploy over), so this is a -Werror, structurally-strict, semantically
# -validated binary whose failure mode is "refuse to emit", never "emit broken".
#
# Consumed by modules/nixos/coredns.nix (which runs `coredns-zone` to produce the
# zone file). At runtime it shells the Dhall library to decode hosts.dhall — the
# registry path is passed with --registry.
{ haskell }:
let
  # GHC 9.12 set (boot libs text/containers come with the compiler).
  hp = haskell.packages.ghc912;
in
hp.callCabal2nix "coredns-zone" ./. { }
