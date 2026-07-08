{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
in
{
  # ── github access-tokens for the daemon (private flake inputs) ──────────────
  # Self-wire the agenix secret holding a nix.conf fragment:
  #   access-tokens = github.com=ghp_…
  # `!include`d into the daemon config below so private inputs
  # (github:sensenet-ai/*) resolve fleet-wide with no hand-exported NIX_CONFIG.
  # Root-owned (the daemon reads it); never the store. A missing file is a soft
  # warning in nix.conf, so this is safe before the secret is first deployed.
  age.secrets.nix-access-tokens.file = flake.self + "/secrets/agenix/machines/nix-access-tokens.age";

  nix = {
    package = pkgs.nixVersions.stable;

    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

    # Merge the agenix-decrypted access-tokens fragment into the daemon config
    # at runtime (keeps the token out of the nix store / the world-readable
    # /etc/nix/nix.conf). `!include` of an absent path only warns.
    extraOptions = ''
      !include /run/agenix/nix-access-tokens
    '';

    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];

      # ── experimental features (incl. pipe operators `|>`) ─────────────────────
      # Set structurally via settings (feeds the generated nix.conf directly);
      # no longer duplicated in extraOptions.
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];

      # ── import-from-derivation, ON by design ───────────────────────────────────
      # We CONSUME typed Dhall (the topology + nativelink fleet config) directly at
      # eval time via `builtins.fromJSON (readFile (runCommand … dhall-to-json …))`
      # — i.e. import-from-derivation. This replaces the old "render Dhall → commit
      # JSON → guard staleness with a -check app" dance: the Dhall is now the SINGLE
      # source of truth with no committed artifact and nothing to keep in sync.
      # IFD is the standard Nix default (and already on here); we pin it true
      # fleet-wide so this reliance is DELIBERATE and documented, not ambient. The
      # one cost — `nix flake check` under `--option allow-import-from-derivation
      # false` (a hypothetical hermetic CI) would break — is accepted; we don't run
      # that mode, and the eval-time `dhall-to-json` build is cheap + cached.
      allow-import-from-derivation = true;

      # Sandbox OFF, fleet-wide. The build sandbox is a category error in the
      # nix evaluation model — purity is a property of the derivation, not of a
      # mount-namespace cage bolted on at realization time (the thing straylight
      # nix corrects with graded monads, where effects are tracked in the type).
      # Concretely it also blocks the buck2 RE drivers (`__noChroot = true`),
      # which need to reach the buck2 daemon / RE fleet. Off here, by design.
      sandbox = false;

      # Binary caches. The private/broken weyl-ai + hyprland cachix caches were
      # removed (they no longer work reliably); keep only the official NixOS
      # cache and the reliable nix-community cache.
      #
      # nativelink.cachix.org is the upstream NativeLink cache. NativeLink is
      # NOT in nixpkgs and builds ~1000 derivations from source, so any host
      # that sets hyper-modern-nixos.nativelink.enable should add this cache
      # (uncomment both the substituter and its key) to avoid a marathon build.
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        # "https://nativelink.cachix.org"
        "https://nix-postgres-artifacts.s3.amazonaws.com"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        # "nativelink.cachix.org-1:Mr5Mc8jLgI/Q8nlmgzqgVfg3pHX8GdW1l8AbWQ4Kit4="
        "nix-postgres-artifacts:dGZlQOvKcNEjvT7QEeBMKja1bMnGqCiQ5vzg4IZ4Qbk="
        # NativeLink Nix cache on guccimane (hyper-modern-nixos.nativelink.nixCache);
        # trusted fleet-wide so any host can substitute its signed paths.
        "nativelink-nix-cache-1:ccYfraJDD/wVIFzw6LJ7psrYahwv4Wztad4XHJcdG4M="
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    # Our own overlay (ragenix/agenix runtime-dep wrapping, inline-snapshot fix).
    # Previously defined as `flake.overlays.default` but never applied anywhere;
    # wiring it here makes it actually take effect on every NixOS system (and,
    # via home-manager.useGlobalPkgs, on their home-manager pkgs too).
    flake.self.overlays.default

    inputs.nix-vscode-extensions.overlays.default

    # Patched attic (sensenet-ai fork): configurable NAR chunk prefetch
    # (chunking.nar-prefetch). Provides pkgs.attic-server / attic-client used by
    # modules/nixos/attic.nix. Fixes serialized R2 chunk GETs on the serve path.
    inputs.attic.overlays.default

    # emacs-pgtk -> 31.x (master). modules/home/emacs uses it.
    inputs.emacs-overlay.overlays.default
    # python312 doc build broken (Sphinx/docutils 0.22 on py3.13)
    (
      final: prev:
      let
        orig-python312 = prev.python312;
      in
      {
        python312 = orig-python312.overrideAttrs (old: {
          passthru = (old.passthru or { }) // {
            doc = final.runCommand "python312-doc" { } ''
              mkdir -p $out/share/doc/python3.12-html
              echo "<html><body>stub</body></html>" > $out/share/doc/python3.12-html/index.html
            '';
          };
        });
      }
    )
  ];
}
