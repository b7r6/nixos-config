# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                  // hyper-modern-nixos // flake // registry
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-contained flake-parts module for the fleet topology + user registry.
#
# Owns:
#   - the NixOS modules: ./nixos.nix (`hyper-modern-nixos.topology`) and
#     ./nixos-users.nix (`hyper-modern-nixos.identity` — the ONE user module)
#   - the typed Dhall registries (./data/) — schema + hosts.dhall + users.dhall
#     (single source of truth; rendered at eval time via IFD, no committed JSON)
#   - the coredns-zone package (./packages/coredns-zone/) — fleet DNS compiler
#   - the admin-recipients-sync check — guards secrets/admin-recipients.json
#     (the agenix operator-key set) against drift from the registry's
#     fleet_admins group. Regenerate with `nix run .#render-admin-recipients`.
{ self, ... }: {
  flake.nixosModules.registry = ./nixos.nix;
  flake.nixosModules.identity = ./nixos-users.nix;

  perSystem = { pkgs, ... }: {
    packages.coredns-zone = pkgs.callPackage ./packages/coredns-zone { };

    checks.admin-recipients-sync =
      pkgs.runCommand "admin-recipients-sync"
        {
          nativeBuildInputs = [
            pkgs.dhall-json
            pkgs.jq
          ];
          LANG = "C.UTF-8";
          LC_ALL = "C.UTF-8";
          LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
        }
        ''
          rendered=$(dhall-to-json --file ${./data}/render-users.dhall \
            | jq -S '[.[] | select(.groups | index("fleet_admins")) | .sshKeys[]] | unique')
          committed=$(jq -S . ${self}/secrets/admin-recipients.json)

          if [ "$rendered" != "$committed" ]; then
            echo "✗ secrets/admin-recipients.json is STALE vs the user registry." >&2
            echo "  regenerate: nix run .#render-admin-recipients (then re-key secrets)" >&2
            diff <(echo "$committed") <(echo "$rendered") >&2 || true
            exit 1
          fi

          echo "✓ admin-recipients.json matches the registry fleet_admins keys"
          touch "$out"
        '';
  };
}
