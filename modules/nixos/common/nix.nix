{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
in
{
  nix = {
    package = pkgs.nixVersions.stable;

    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

    extraOptions = ''
      experimental-features = nix-command flakes pipe-operators
    '';

    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];

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
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        # "nativelink.cachix.org-1:Mr5Mc8jLgI/Q8nlmgzqgVfg3pHX8GdW1l8AbWQ4Kit4="
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
