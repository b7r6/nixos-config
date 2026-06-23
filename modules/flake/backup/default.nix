# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // flake // backup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-contained flake-parts module for the restic backup subsystem.
#
# Owns:
#   - the NixOS module (./nixos.nix) — `hyper-modern-nixos.backup`
#   - the VM test (./checks/restic.nix)
#   - the `restic-init` flake app
#
# This directory is the unit of extraction: `git mv` it into a standalone flake,
# add a `flake.nix` wrapper, and consume it as an input.
#
# ─── dependencies ─────────────────────────────────────────────────────────────
# The NixOS module reads `config.hyper-modern-nixos.state.authoritativePaths`
# (from modules/nixos/state.nix, a core cross-cutting option). On extraction,
# that becomes an optional integration: if the importing system defines the
# option, it is used; otherwise the paths list is just `cfg.paths`.
#
# ─────────────────────────────────────── "Trust, but verify the restore." ─────
{ inputs, self, ... }:
{
  flake.nixosModules.backup = ./nixos.nix;

  perSystem = { pkgs, system, ... }: {
    # ── checks ────────────────────────────────────────────────────────────────
    checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      backup-restic = import ./checks/restic.nix { inherit pkgs inputs; };
    };

    # ── apps ──────────────────────────────────────────────────────────────────
    # `nix run .#restic-init -- <host>` — trigger the one-time, idempotent
    # restic-backups-init.service on a host over the tailnet (or locally). The
    # unit uses the host's own agenix-decrypted password/env, so there's nothing
    # to pass but the hostname.
    apps.restic-init = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "restic-init";
          runtimeInputs = [ pkgs.openssh ];
          text = ''
            host="''${1:-}"
            if [ -z "$host" ]; then
              echo "usage: nix run .#restic-init -- <host>" >&2
              echo "  triggers restic-backups-init.service on <host> (idempotent)." >&2
              exit 1
            fi
            if [ "$host" = "$(hostname)" ]; then
              sudo systemctl start --wait restic-backups-init.service
              sudo journalctl -u restic-backups-init.service -n 20 --no-pager
            else
              # shellcheck disable=SC2029
              ssh "$host" 'sudo systemctl start --wait restic-backups-init.service \
                && sudo journalctl -u restic-backups-init.service -n 20 --no-pager'
            fi
          '';
        }
      );
    };
  };
}
