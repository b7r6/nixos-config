# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hypermodern // nix // cache-push
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# `push-flake` — build every output of a flake for this system and push each
# path's whole closure to the nix_cache. The tool lives in the nativelink fork
# (it wraps the `nl-nix` client that flake ships); this just re-exports it so
# `nix run .#push-flake [-- FLAKE]` works fleet-side too.
#
#   nix run .#push-flake                 # the flake in $PWD -> local cache
#   nix run .#push-flake -- ~/src/foo    # a specific flake
#   NL_PUSH_OUTPUTS="packages devShells checks" NL_NIX_CACHE=… nix run .#push-flake
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{ inputs, ... }: {
  perSystem = { system, ... }: { apps.push-flake = inputs.nativelink-nix.apps.${system}.push-flake; };
}
