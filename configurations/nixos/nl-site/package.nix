# The NativeLink package a site soaks, from the flake input its
# `nativelinkRev.input` names (hypermodern-nativelink's sites.dhall), asserted
# to be locked at the rev the site says: a drifted lock refuses to evaluate
# rather than quietly soaking something else. Shared by the generated sites
# (../../sites.nix) and the hand-written az site (../nl-az/node.nix), so both
# soak exactly what sites.dhall records.
#
#   packageFor site  → null (the fork module's default, the `nativelink-nix`
#                       input) when the site soaks that, else the named
#                       input's x86_64-linux `nativelink`
{ inputs, lib }:
site:
let
  rev = site.nativelinkRev;
  input =
    inputs.${rev.input}
      or (throw "site ${site.name}: nativelinkRev.input '${rev.input}' is not a flake input (add it to flake.nix)");
in
assert lib.assertMsg (input.rev == rev.rev)
  "site ${site.name}: input ${rev.input} is locked at ${input.rev}, sites.dhall says ${rev.rev}";
if rev.input == "nativelink-nix" then null else input.packages.x86_64-linux.nativelink
