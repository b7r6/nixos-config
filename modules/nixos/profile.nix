# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hypermodern // nixos // profile
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# ONE switch that decides how much of a host is built: `full` (everything the
# host declares) or `bootstrap` (a bootable encrypted desktop that needs NO
# from-source fork builds — only what public caches carry, plus cheap config
# derivations). Every host gets a `<name>-bootstrap` nixosConfiguration for
# free (configurations/default.nix), so a reinstall is always:
#
#     nixos-install --flake .#<host>-bootstrap     # minutes, fits in RAM
#     reboot
#     nh os switch .#<host>                        # the full thing, at leisure
#
# Why this exists: `disko-install` / `nixos-install` from a stock ISO have no
# access to this fleet's own nix_cache, so anything that is not on
# cache.nixos.org / nix-community compiles on the target — on a 13" laptop
# with a tmpfs store that is a silent OOM hang, not a slow install (shannon,
# 2026-10). The bootstrap profile mkForces every such burden off, centrally,
# so no host config needs commenting-out surgery before a reinstall.
#
# The home-manager side lives in modules/home/profile.nix; this module
# propagates the value to every HM user that carries the option.
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos;
  bootstrap = cfg.profile == "bootstrap";
  off = lib.mkForce false;
in
{
  options.hyper-modern-nixos.profile = lib.mkOption {
    type = lib.types.enum [
      "full"
      "bootstrap"
    ];
    default = "full";
    description = ''
      Build profile. `full` is the host as declared. `bootstrap` is the same
      host with every from-source / fleet-service burden forced off: enough to
      boot an encrypted desktop from a stock installer ISO, then switch to
      `full` from the installed system. Set via the `<host>-bootstrap`
      nixosConfiguration; never by hand in a host config.
    '';
  };

  config = lib.mkIf bootstrap {
    # ── Fleet services: all from-source forks or needing fleet secrets/peers ──
    hyper-modern-nixos = {
      # nativelink (Rust, musl cross, ~640 drvs, NO public cache). The fleet
      # default turns the nix_cache on for every host — the single biggest
      # install burden on the fleet.
      nativelink.enable = off;
      nativelink.nixCache.enable = off;
      nativelink.nixCache.watchStore = off;

      # coredns-zone (Haskell), clickhouse (C++), otel collectors, nginx edge:
      # the server stack. None of it is needed to boot a desktop.
      coredns.enable = off;
      databases.clickhouse.keeper.enable = off;
      databases.clickhouse.server.enable = off;
      observability.otel.agent.enable = off;
      observability.otel.gateway.enable = off;
      reverseProxy.enable = off;

      # rclone mounts want R2 credentials from agenix; harmless but pointless
      # before /home is restored and the host key is in place.
      # (backup.enable stays as declared — see the timer note below)
      rcloneMount.enable = off;

      # The profiling toolchain (bpftrace, bcc, valgrind, …) is cached but
      # large; it comes back with the full profile.
      performance.tools = off;
    };

    # ── restic timer ─────────────────────────────────────────────────────────
    # restic itself stays (cached; `restic-system restore` is how /home comes
    # back on first boot) but its hourly Persistent=true timer must NOT fire
    # before that restore — it would snapshot an empty /home as `latest` within
    # minutes of boot. The full profile brings the timer back.
    systemd.timers.restic-backups-system.enable = lib.mkIf config.hyper-modern-nixos.backup.enable (
      lib.mkForce false
    );

    # ── Propagate to home-manager ────────────────────────────────────────────
    # Guarded on the option existing so an HM user that does NOT import
    # homeModules.default (e.g. an inline test user) is unaffected.
    home-manager.sharedModules = [
      ({ options, ... }: {
        config = lib.optionalAttrs (options ? hyper-modern-nixos && options.hyper-modern-nixos ? profile) {
          hyper-modern-nixos.profile = cfg.profile;
        };
      })
    ];
  };
}
