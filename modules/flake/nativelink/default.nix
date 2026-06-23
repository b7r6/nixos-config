# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                 // hyper-modern-nixos // flake // nativelink
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-contained flake-parts module for NativeLink remote execution.
#
# Owns:
#   - the NixOS module (./nixos.nix) — `hyper-modern-nixos.nativelink`
#   - the typed Dhall fleet config (./data/) — schema, fleet, rendered out/*.json
#   - render + staleness-check apps
#
# This directory is the unit of extraction: `git mv` it into a standalone flake,
# add a `flake.nix` wrapper, and consume it as an input.
#
# ─── dependencies ─────────────────────────────────────────────────────────────
# The NixOS module reads:
#   - `flake.inputs.nativelink` (the nativelink flake for the binary package)
#   - `flake.self` (to locate data/out/<host>.json)
#   - `config.hyper-modern-nixos.state` (from modules/nixos/state.nix)
# On extraction, these become the flake's own inputs + an optional integration.
_: {
  flake.nixosModules.nativelink = ./nixos.nix;

  perSystem = { pkgs, ... }: {
    # ── apps ──────────────────────────────────────────────────────────────────

    # `nix run .#nativelink-render` — render the typed Dhall fleet config to the
    # committed data/out/<host>.json (one per fleet host). Dhall is the source of
    # truth; committed JSON is IFD-free. Run after editing data/*.dhall.
    apps.nativelink-render = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "nativelink-render";
          runtimeInputs = [
            pkgs.dhall-json
            pkgs.jq
          ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root/modules/flake/nativelink/data"
            mkdir -p out
            dhall-to-json --file render-all.dhall | jq -c '.[]' | while read -r item; do
              host=$(echo "$item" | jq -r .host)
              echo "$item" | jq -r .json | jq . > "out/$host.json"
              echo "// nativelink // rendered out/$host.json"
            done
            echo "// nativelink // done (commit modules/flake/nativelink/data/out/*.json)"
          '';
        }
      );
    };

    # `nix run .#nativelink-check` — verify committed out/*.json match the Dhall.
    apps.nativelink-check = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "nativelink-check";
          runtimeInputs = [
            pkgs.dhall-json
            pkgs.jq
            pkgs.diffutils
          ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root/modules/flake/nativelink/data"
            # Render to a temp dir and diff the whole tree — avoids the
            # subshell-`exit` gotcha (a `while | read` pipeline runs in a subshell,
            # so an `exit 1` inside it can't fail the script).
            tmp="$(mktemp -d)"
            trap 'rm -rf "$tmp"' EXIT
            dhall-to-json --file render-all.dhall | jq -c '.[]' > "$tmp/items"
            while read -r item; do
              host=$(echo "$item" | jq -r .host)
              echo "$item" | jq -r .json | jq . > "$tmp/$host.json"
            done < "$tmp/items"
            ok=1
            for f in out/*.json; do
              host="$(basename "$f" .json)"
              if ! diff -u "$f" "$tmp/$host.json" >/dev/null 2>&1; then
                echo "// nativelink // STALE: $f (run: nix run .#nativelink-render)" >&2
                ok=0
              fi
            done
            if [ "$ok" -eq 1 ]; then
              echo "// nativelink // out/*.json in sync with the Dhall fleet"
            else
              exit 1
            fi
          '';
        }
      );
    };
  };
}
