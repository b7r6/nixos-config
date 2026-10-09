# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // overlay
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

final: prev: {

  # claude-code — bumped ahead of nixpkgs (which lagged at 2.1.195). It's a
  # prebuilt-binary fetch, so overriding version + src is a clean targeted bump
  # that doesn't rebuild the world via a nixpkgs update. linux-x64 is fine: the
  # fleet is one x86_64 box now. Refresh the hash with:
  #   nix store prefetch-file https://downloads.claude.ai/claude-code-releases/<v>/linux-x64/claude
  # TODO[b7r6]: override DROPPED for the modern-nixpkgs migration. We used to pin
  # 2.1.293 ahead of the stale fork (which lagged at 2.1.195); modern nixpkgs
  # already ships 2.1.292, and the fetchurl override breaks against its updated
  # base derivation. Re-pin here only if nixpkgs falls behind again.
  # claude-code = prev.claude-code.overrideAttrs (_old: {
  #   version = "2.1.293";
  #   src = prev.fetchurl {
  #     url = "https://downloads.claude.ai/claude-code-releases/2.1.293/linux-x64/claude";
  #     hash = "sha256-iWhAXibbR4r0TqvEY1q1ylVwV7cCpURgpZwT4bJT6Xg=";
  #   };
  # });

  # fleet-orbit — Secureframe's osquery agent (static Go binary, fetched durably
  # from cdn.s4.gl). See packages/fleet-orbit/default.nix.
  fleet-orbit = prev.callPackage ../../packages/fleet-orbit { };

  # coredns-zone — the fleet DNS compiler (modules/flake/registry/packages/coredns-zone):
  # a compiled GHC-9.12 program that renders + semantically validates the topology
  # registry into a CoreDNS zone. Consumed by modules/nixos/coredns.nix at build time.
  coredns-zone = prev.callPackage ../flake/registry/packages/coredns-zone { };

  # state-audit — validates state classification against data-loss invariants.
  state-audit = prev.callPackage ../../packages/state-audit { };

  # gen-supabase-secrets — compiled JWT/crypto generator (replaces bash).
  gen-supabase-secrets = prev.callPackage ../../packages/gen-supabase-secrets { };

  # Python test-suite skips, applied at the INTERPRETER level (packageOverrides)
  # so they propagate to TRANSITIVE consumers — a `python312Packages // {…}`
  # override only fixes the top-level attr, not packages that pull these as deps.
  #   - anyio: its trio / asyncio-TLS tests fail intermittently on nixos-unstable
  #     ("unraisable exception warnings"); the library is fine, the tests flake.
  #   - inline-snapshot: trivial output-format diff upstream.
  python312 = prev.python312.override (old: {
    packageOverrides = prev.lib.composeExtensions (old.packageOverrides or (_: _: { })) (
      _pyfinal: pyprev: {
        anyio = pyprev.anyio.overridePythonAttrs (_: { doCheck = false; });
        inline-snapshot = pyprev.inline-snapshot.overridePythonAttrs (_: { doCheck = false; });
      }
    );
  });
  python312Packages = final.python312.pkgs;

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
