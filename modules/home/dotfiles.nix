# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // dotfiles
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The repo-homed config model: editor (and eventually other) configs live in
# THIS repo under dotfiles/, and XDG locations get out-of-store symlinks
# pointing back at the working tree. Nix's job is to accelerate (binaries,
# LSPs, grammars on PATH) — never to own the config. The configs themselves
# guard every nix-specific reference, so a plain `git clone` + symlink on any
# distro yields a working (if less pre-loaded) setup.
#
# Consequences:
#   - editing config never requires a rebuild; edits through the symlink land
#     in `git diff` immediately
#   - the store never holds the live config, so nothing is read-only
#   - the path below must point at a real checkout; activation warns if not
#
{
  config,
  lib,
  ...
}:
{
  options.hyper-modern-nixos.dotfiles = {
    path = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/src/nixos-config/dotfiles";
      description = ''
        Absolute path to the dotfiles/ directory of the live nixos-config
        checkout. XDG config locations are symlinked INTO this working tree
        (out-of-store), so config edits are instant and land in git.
      '';
    };
  };

  config = {
    # A missing checkout means every dotfiles symlink dangles — say so loudly
    # (but don't fail activation: first boot may precede the clone).
    home.activation.dotfilesCheckout = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "${config.hyper-modern-nixos.dotfiles.path}" ]; then
        warnEcho "[dotfiles] ${config.hyper-modern-nixos.dotfiles.path} does not exist — repo-homed configs are dangling symlinks until the checkout appears"
      fi
    '';
  };
}
