# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                // hyper-modern-nixos // state
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# ONE classification of mutable state, consumed by both impermanence and restic.
# See docs/src/architecture/state-and-backup.md for the full model.
#
# A service declares its state directory ONCE, with a class:
#
#   hyper-modern-nixos.state.dirs.<name> = {
#     path  = "/var/lib/foo";
#     class = "authoritative";   # | "reconstructible" | "ephemeral"
#   };
#
# from which two views are DERIVED (so they can never drift):
#
#   - impermanence persist-list  ← authoritative ∪ reconstructible
#       (precious data survives a reboot; so does an expensive-to-refetch cache)
#   - restic backup paths        ← authoritative
#       (only irreplaceable, app-managed data goes to R2)
#
# This module owns no schedule and starts no service; it is pure plumbing that
# other modules (backup.nix, impermanence.nix) read via the two read-only
# outputs `authoritativePaths` / `persistPaths`. Layout stays /var/lib-native —
# the class, not the directory name, carries the backup/persist semantics.
{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.state;

  inherit (lib)
    mkOption
    types
    attrValues
    filter
    catAttrs
    unique
    ;

  dirsOfClass = c: filter (d: d.class == c) (attrValues cfg.dirs);
  pathsOfClass = c: catAttrs "path" (dirsOfClass c);

  authoritative = pathsOfClass "authoritative";
  # Persisted = anything worth surviving a reboot: precious OR expensive cache.
  persist = unique (pathsOfClass "authoritative" ++ pathsOfClass "reconstructible");
in
{
  options.hyper-modern-nixos.state = {
    dirs = mkOption {
      default = { };
      description = ''
        Mutable-state directories declared by services, each with a class that
        decides whether it is persisted across an impermanence reboot and/or
        backed up to R2. The single source of truth for state classification.
      '';
      example = lib.literalExpression ''
        {
          forgejo  = { path = "/var/lib/forgejo"; class = "authoritative"; };
          atticd   = { path = "/var/lib/atticd";  class = "reconstructible"; };
        }
      '';
      type = types.attrsOf (
        types.submodule (
          _: {
            options = {
              path = mkOption {
                type = types.str;
                description = "Absolute path to the state directory.";
              };
              class = mkOption {
                type = types.enum [
                  "authoritative"
                  "reconstructible"
                  "ephemeral"
                ];
                description = ''
                  - authoritative: irreplaceable, app-managed → persisted AND backed up.
                  - reconstructible: cache/CAS whose truth is in R2 / re-derivable →
                    persisted (avoid slow refetch on reboot) but NOT backed up.
                  - ephemeral: scratch → neither persisted nor backed up.
                '';
              };
            };
          }
        )
      );
    };

    # ── Read-only derived views (other modules consume these) ───────────────────
    authoritativePaths = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = unique authoritative;
      description = "DERIVED: state paths to back up (class = authoritative).";
    };

    persistPaths = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = persist;
      description = "DERIVED: state paths to persist across an impermanence reboot.";
    };
  };

  # No `config` block: state.nix is pure plumbing with zero coupling to the
  # optional impermanence / backup modules. Consumers READ the derived outputs:
  #   - backup.nix reads state.authoritativePaths → unions into restic paths.
  #   - impermanence.nix reads state.persistPaths → unions into its persist list.
  # Inverting the dependency this way means state.nix can be imported on its own
  # (e.g. in a nixosTest) without dragging in impermanence or backup.
}
