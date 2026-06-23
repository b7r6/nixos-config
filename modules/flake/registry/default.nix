# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                  // hyper-modern-nixos // flake // registry
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-contained flake-parts module for the fleet topology registry.
#
# Owns:
#   - the NixOS module (./nixos.nix) — `hyper-modern-nixos.topology`
#   - the typed Dhall registry (./data/) — schema, hosts, committed registry.json
#   - the coredns-zone package (./packages/coredns-zone/) — fleet DNS compiler
#   - render + staleness-check apps
#
# This directory is the unit of extraction: `git mv` it into a standalone flake,
# add a `flake.nix` wrapper, and consume it as an input.
#
# ─── dependencies ─────────────────────────────────────────────────────────────
# The NixOS module reads `flake.self + "/modules/flake/registry/data/registry.json"`.
# The coredns-zone package is also surfaced via the overlay (for coredns.nix).
{ inputs, self, ... }:
{
  flake.nixosModules.registry = ./nixos.nix;

  perSystem = { pkgs, ... }: {
    # ── packages ──────────────────────────────────────────────────────────────
    packages.coredns-zone = pkgs.callPackage ./packages/coredns-zone { };

    # ── apps ──────────────────────────────────────────────────────────────────

    # `nix run .#topology-render` — render the Dhall topology registry to the
    # committed data/registry.json. Dhall is the source of truth; the JSON is
    # a committed artifact (no import-from-derivation, so `nix flake check` works).
    # Run after editing data/*.dhall, then commit the regenerated JSON.
    apps.topology-render = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "topology-render";
          runtimeInputs = [ pkgs.dhall-json ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root/modules/flake/registry/data"
            dhall-to-json --file hosts.dhall > registry.json
            echo "// topology // rendered registry.json (commit it)"
          '';
        }
      );
    };

    # `nix run .#topology-check` — verify the committed registry.json is in sync
    # with the Dhall source (CI/pre-commit guard against a stale artifact).
    apps.topology-check = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "topology-check";
          runtimeInputs = [
            pkgs.dhall-json
            pkgs.diffutils
          ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root/modules/flake/registry/data"
            if ! dhall-to-json --file hosts.dhall | diff -u registry.json - ; then
              echo "// topology // registry.json is STALE — run: nix run .#topology-render" >&2
              exit 1
            fi
            echo "// topology // registry.json is in sync with hosts.dhall"
          '';
        }
      );
    };
  };
}
