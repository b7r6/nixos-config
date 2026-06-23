# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                               // hyper-modern-nixos // overlay
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The repo-wide nixpkgs overlay. This is a PLAIN overlay function
# (`final: prev: { ... }`) so it can be imported directly into
# `nixpkgs.overlays` from both NixOS modules and standalone home-manager.
#
# It is ALSO surfaced as the flake output `self.overlays.default` via
# modules/flake/overlays.nix, for external consumers.
#
# History: this overlay used to be declared as `flake.overlays.default` inside
# this file, but it lived under modules/overlays/ which nixos-unified's autoWire
# does NOT import (only modules/flake/* is autowired), so it was a dead no-op
# and `self.overlays.default` evaluated to nothing. It is now wired explicitly.

_final: prev: {

  # zot OCI registry — not in nixpkgs, packaged in-repo (packages/zot).
  zot = prev.callPackage ../../packages/zot { };

  # Skip failing inline-snapshot tests (trivial output format diff in upstream).
  # TODO: remove once upstream is fixed.
  python312Packages = prev.python312Packages // {
    inline-snapshot = prev.python312Packages.inline-snapshot.overridePythonAttrs (_old: {
      doCheck = false;
    });
  };

  # ragenix ships without its runtime deps on PATH; wrap it so the CLI actually
  # finds sha256sum/find/grep/sed/rage/age at runtime.
  ragenix = prev.ragenix.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
    postInstall = (old.postInstall or "") + ''
      wrapProgram $out/bin/ragenix \
        --prefix PATH : ${
          prev.lib.makeBinPath [
            prev.coreutils # sha256sum
            prev.findutils # find
            prev.gnugrep # grep
            prev.gnused # sed
            prev.rage # rage
            prev.age # age
          ]
        }
    '';
  });

  # Same treatment for agenix, guarded in case the attr is absent.
  agenix =
    if prev ? agenix then
      prev.agenix.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
        postInstall = (old.postInstall or "") + ''
          wrapProgram $out/bin/agenix \
            --prefix PATH : ${
              prev.lib.makeBinPath [
                prev.coreutils
                prev.findutils
                prev.gnugrep
                prev.gnused
                prev.rage
                prev.age
              ]
            }
        '';
      })
    else
      prev.agenix or null;
}
