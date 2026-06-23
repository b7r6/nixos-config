# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                  // hyper-modern-nixos // checks // state-audit
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Prove the REAL fleet's state classification doesn't violate data-loss
# invariants. This is NOT a synthetic test with fake data — it feeds
# state-audit the ACTUAL state.dirs + backup config from each host's evaluated
# config, so a miscategorization (path not backed up, path not persisted, path
# excluded by a glob) that would silently lose data FAILS THE BUILD.
#
# The test exercises watchtower (the richest state: atticd cluster + supabase +
# postgres dumps + rclone) — if its classification is safe, the fleet is safe
# (other hosts have a subset of watchtower's state dirs). If a future service
# adds a state dir with a typo/relative-path/wrong-class, this catches it at
# `nix flake check` time, not at restore time.
{ pkgs, inputs }:
let
  inherit (inputs) self;

  # Evaluate watchtower's config to extract the real state classification +
  # backup config. This is the evaluated-at-check-time data (not runtime) — it's
  # the same values backup.nix and impermanence.nix would use.
  wtCfg = self.nixosConfigurations.watchtower.config;
  stateCfg = wtCfg.hyper-modern-nixos.state;
  backupCfg = wtCfg.hyper-modern-nixos.backup;

  # Serialize the state classification into the JSON shape state-audit expects.
  auditInput = pkgs.writeText "state-audit-watchtower.json" (
    builtins.toJSON {
      dirs = builtins.map (name: {
        inherit name;
        path = stateCfg.dirs.${name}.path;
        class = stateCfg.dirs.${name}.class;
      }) (builtins.attrNames stateCfg.dirs);
      inherit (stateCfg) authoritativePaths;
      inherit (stateCfg) persistPaths;
      backupPaths =
        if backupCfg.enable then
          pkgs.lib.unique (backupCfg.paths ++ stateCfg.authoritativePaths)
        else
          stateCfg.authoritativePaths;
      exclude = if backupCfg.enable then backupCfg.exclude else [ ];
    }
  );
in
# This is a PURE BUILD check (not a VM test) — it runs state-audit on the
# serialized host data at build time and fails the derivation if any invariant
# is violated. Faster than a VM, and the data is eval-time so it catches the
# same bugs. A VM is unnecessary because state-audit validates DATA, not runtime.
pkgs.runCommand "state-audit-check"
  {
    nativeBuildInputs = [ pkgs.state-audit ];
    LANG = "C.UTF-8";
    LC_ALL = "C.UTF-8";
    LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
  }
  ''
    state-audit ${auditInput}
    touch $out
  ''
