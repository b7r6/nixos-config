# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // fhs-bin
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# A populated /bin and /usr/bin, for code that assumes an Ubuntu-shaped host
# (gated; on by default wherever NativeLink runs). NixOS ships only /bin/sh and
# /usr/bin/env, and two things in a "relatively normal" NativeLink reach past
# them:
#
#   - absolute paths: Bazel's default --shell_executable is the literal
#     /bin/bash (every genrule), scripts carry #!/bin/bash, REAPI actions name
#     /bin/true, and the worker tests hard-code /bin/bash and /usr/bin/bash.
#   - PATH-less spawns: the worker runs query_cmd properties (and the tests
#     their helpers) with env_clear(), so libc falls back to its default search
#     path. NativeLink is static musl, whose default is /usr/local/bin:/bin:
#     /usr/bin, so `bash -c …` or `printf …` resolves there or nowhere. (Nix's
#     glibc adds /run/current-system/sw/bin, which hides this from `env -i`.)
#
# envfs alone does NOT cover the second: it resolves /bin/<x> against the
# exec'd env's PATH, then the caller's own, then a fallback-path that holds
# only sh and env. A Bazel test's caller has a rich PATH, so it passes; the
# NativeLink worker is a systemd service with a sparse one, so its actions kept
# exiting 127 with envfs mounted (verified on az2). So two backends: real
# symlinks by default, or, on a host that runs envfs (shannon: it also serves
# arbitrary /usr/bin/<x> to interactive scripts), the same set appended to
# envfs's fallback-path.
#
# The set is the fork's floor baseline (nixos/module.nix `floorBaseline`), the
# same tools the worker entrypoint puts on PATH for remote actions, linked into
# both directories because Ubuntu 24.04 (CI) is merged-/usr. Not hermetic and
# not meant to be: hermetic actions name /nix/store paths; this is for the ones
# that don't. bashInteractive, not bash, so /bin/bash is the same derivation as
# /bin/sh.
#
# NixOS-owned entries (/bin/sh from binsh, /usr/bin/env from usrbinenv) and
# anything that is not a /nix/store symlink (fleet-orbit's /usr/bin/sudo →
# /run/wrappers) are left alone. Links are identified by pointing into the
# baseline env, so a shrunk set, or turning the module off, removes exactly
# what this module put there.
#
{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.fhsBin;

  envName = "hyper-modern-fhs-bin";
  baseline = pkgs.buildEnv {
    name = envName;
    paths = cfg.packages;
    pathsToLink = [ "/bin" ];
  };
  wanted = if cfg.enable then "${baseline}/bin" else "";
in
{
  options.hyper-modern-nixos.fhsBin = {
    enable = mkEnableOption "hyper-modern-nixos.fhsBin" // {
      default = config.hyper-modern-nixos.nativelink.enable;
      defaultText = literalExpression "config.hyper-modern-nixos.nativelink.enable";
    };
    packages = mkOption {
      type = types.listOf types.package;
      default = with pkgs; [
        bashInteractive
        coreutils
        findutils
        gnused
        gnugrep
        gawk
        gnutar
        gzip
        xz
      ];
      description = "Packages whose bin/ entries are linked into /bin and /usr/bin.";
    };
  };

  config = mkMerge [
    (mkIf (cfg.enable && config.services.envfs.enable) {
      services.envfs.extraFallbackPathCommands = ''
        for src in ${baseline}/bin/*; do
          [ -e "$out/''${src##*/}" ] || ln -s "$src" "$out/"
        done
      '';
    })
    # envfs owns /bin and /usr/bin (read-only FUSE) where it runs; elsewhere this
    # runs when disabled too (with an empty set), so turning it off cleans up.
    (mkIf (!config.services.envfs.enable) {
      system.activationScripts.fhsBin = {
        deps = [ "binsh" ] ++ optional (config.environment.usrbinenv != null) "usrbinenv";
        text = ''
          wanted=${escapeShellArg wanted}
          # an earlier generation mounted envfs over /bin (read-only FUSE); drop it
          if [ -n "$wanted" ] && ${pkgs.util-linux}/bin/mountpoint -q /bin; then
            ${pkgs.util-linux}/bin/umount -l /bin || true
          fi
          for dir in /bin /usr/bin; do
            mkdir -p "$dir"
            if [ -n "$wanted" ]; then
              for src in "$wanted"/*; do
                dst="$dir/''${src##*/}"
                case "$dst" in /bin/sh | /usr/bin/env) continue ;; esac
                if [ -e "$dst" ] || [ -L "$dst" ]; then
                  [ -L "$dst" ] && [[ "$(readlink "$dst")" == /nix/store/* ]] || continue
                fi
                ln -sfn "$src" "$dst.fhs-bin-new" && mv -fT "$dst.fhs-bin-new" "$dst"
              done
            fi
            for dst in "$dir"/*; do
              [ -L "$dst" ] || continue
              [[ "$(readlink "$dst")" == /nix/store/*-${envName}/bin/* ]] || continue
              [ -n "$wanted" ] && [ -e "$wanted/''${dst##*/}" ] || rm -f "$dst"
            done
          done
        '';
      };
    })
  ];
}
