# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                             // hypermodern // home // profile
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Home-manager half of the build profile (see modules/nixos/profile.nix for
# the rationale). Under NixOS the value is propagated from the host; under a
# standalone `nh home switch` it defaults to `full`.
#
# `bootstrap` keeps the desktop, the shell, the terminal and Emacs — and drops
# every package that only exists as a from-source build of one of our own
# forks (narsil, the nativelink client, wintermute) or that is simply large and
# not needed on first boot (VS Code + extensions, cloud CLIs, the heavy LSPs).
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
      Build profile; mirrors the NixOS option of the same name and is set from
      it. `bootstrap` forces every from-source / heavyweight home package off.
    '';
  };

  config = lib.mkIf bootstrap {
    hyper-modern-nixos = {
      # Our own forks — no public cache, hours of compile on a laptop.
      narsil.enable = off; # Haskell
      nix.nativelinkClient.enable = off; # Rust (nl-nix / nl-watch-store)
      new-suzuki.wintermute.enable = off; # Lean 4 (the shell itself stays)

      # Heavy but cached: dropped purely to keep the first closure small.
      vscode.enable = off;
      cloud.aws.enable = off;
      cloud.flyctl.enable = off;
      cloud.gcp.enable = off;
      cloud.terraform.enable = off;
      emacs.haskell.enable = off;
      emacs.lean4.enable = off;
      emacs.purescript.enable = off; # local npm builds (purs-tidy, purescript-language-server)
    };
  };
}
