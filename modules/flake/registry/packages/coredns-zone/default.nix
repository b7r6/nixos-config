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
# Consumed by the coredns NixOS module (which runs `coredns-zone` to produce the
# zone file). At runtime it uses the Dhall library to decode hosts.dhall — the
# registry path is passed with --registry.
#
# IFD-free: the cabal2nix output is pre-generated (./generated.nix) so cross-arch
# evaluation (aarch64 shimmer from x86_64) works without building cabal2nix at
# eval time. Re-generate with: `cabal2nix . > generated.nix`
{ haskell }:
let
  # GHC 9.12 set (boot libs text/containers come with the compiler).
  hp = haskell.packages.ghc912;
in
hp.callPackage ./generated.nix { }
