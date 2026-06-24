# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                          // hyper-modern-nixos // flake
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Root flake-parts module. Imports all sub-modules; the only perSystem here is
# the devshell and the font packages that don't belong to any component.
{ inputs, ... }: {
  debug = true;

  # ── flakeModules output (the extraction seam) ──────────────────────────────
  # When a component graduates to its own flake, it exposes
  # `flakeModules.default` and consumers swap the path import for an input.
  flake.flakeModules = {
    attic = ./attic;
    backup = ./backup;
    coredns = ./coredns;
    media = ./media;
    nativelink = ./nativelink;
    registry = ./registry;
    themes = ./themes;
  };

  imports = [
    # ── infrastructure (cross-cutting) ──
    inputs.devshell.flakeModule
    ./pkgs.nix
    ./fmt.nix
    ./overlays.nix
    ./devshell.nix
    ./deploy.nix
    ./usb.nix
    ./docs.nix

    # ── component flake-modules (future-flake candidates) ──
    ./attic
    ./backup
    ./coredns
    ./media
    ./nativelink
    ./registry
    ./themes

    # ── secrets administration subsystem ──
    ../../secrets
  ];

  perSystem = { pkgs, system, ... }: {
    devshells.default.imports = [ (pkgs.devshell.importTOML ../../devshell.toml) ];

    packages = {
      berkeley-mono = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
      default = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
      ono-sendai-generator = pkgs.callPackage ./themes/packages/ono-sendai-generator { };
      state-audit = pkgs.callPackage ../../packages/state-audit { };
      gen-supabase-secrets = pkgs.callPackage ../../packages/gen-supabase-secrets { };
      supabase-postgres-meta = pkgs.callPackage ../../packages/supabase-postgres-meta { };
    };

    # Cross-cutting check: validates the fleet's state classification.
    checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      state-audit = import ../../checks/state-audit.nix { inherit pkgs inputs; };
    };
  };
}
