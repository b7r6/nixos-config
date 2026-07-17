# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hypermodern // nix // cache-push
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# `push-flake [FLAKE]` — build every output of a flake for THIS system and push
# each path's whole closure to the NativeLink nix_cache. The "build everything
# here, upload it all" button.
#
#   push-flake                 # the flake in $PWD -> local cache
#   push-flake ~/src/foo       # a specific flake
#   NL_PUSH_OUTPUTS="packages devShells checks" push-flake
#   NL_NIX_CACHE=http://host:50071/nix/main push-flake
#
# Enumerates via `nix eval` per output type (robust: a sibling output that
# doesn't evaluate can't sink the whole run, unlike a global `nix flake show`).
# Pushes with `nl-nix --recursive` (the proven client); signs with the fleet key
# when the host has it (root), otherwise the cache signs on serve.
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      nlnix = inputs.nativelink-nix.packages.${system}.nativelink-nix-client;
      push-flake = pkgs.writeShellApplication {
        name = "push-flake";
        runtimeInputs = [
          pkgs.nix
          pkgs.jq
          nlnix
        ];
        text = ''
          set -euo pipefail

          flake="''${1:-.}"
          cache="''${NL_NIX_CACHE:-http://127.0.0.1:50071/nix/main}"
          outputs="''${NL_PUSH_OUTPUTS:-packages devShells}"
          system="$(nix eval --raw --impure --expr builtins.currentSystem)"

          echo "// push-flake // flake=$flake  system=$system  cache=$cache  outputs=[$outputs]"

          # Enumerate buildable attrs for this system, one output type at a time.
          attrs=()
          for kind in $outputs; do
            names="$(nix eval --json "$flake#$kind.$system" --apply builtins.attrNames 2>/dev/null || echo '[]')"
            while IFS= read -r name; do
              [ -n "$name" ] && attrs+=("$kind.$system.$name")
            done < <(printf '%s' "$names" | jq -r '.[]')
          done

          if [ "''${#attrs[@]}" -eq 0 ]; then
            echo "// push-flake // no buildable outputs for $system in [$outputs]" >&2
            exit 0
          fi

          installables=()
          for a in "''${attrs[@]}"; do installables+=("$flake#$a"); done
          echo "// push-flake // building ''${#attrs[@]} outputs:"
          printf '  %s\n' "''${attrs[@]}"

          # Build all; --keep-going so one broken output doesn't sink the rest
          # (failures still print to stderr). stdout is only the out paths.
          mapfile -t outs < <(nix build --no-link --keep-going --print-out-paths "''${installables[@]}")
          if [ "''${#outs[@]}" -eq 0 ]; then
            echo "// push-flake // nothing built" >&2
            exit 1
          fi

          # Sign with the fleet key if the host has it (root); otherwise the
          # cache re-signs on serve. Push each path's entire reference closure.
          signing=()
          if [ -r /run/agenix/nativelink-nix-cache-key ]; then
            signing=(--signing-key /run/agenix/nativelink-nix-cache-key)
          fi
          echo "// push-flake // built ''${#outs[@]} paths; pushing closures to $cache"
          nl-nix --to "$cache" "''${signing[@]}" push --recursive "''${outs[@]}"
          echo "// push-flake // done"
        '';
      };
    in
    {
      packages.push-flake = push-flake;
      apps.push-flake = {
        type = "app";
        program = pkgs.lib.getExe push-flake;
      };
    };
}
