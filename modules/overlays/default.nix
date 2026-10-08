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

_final: prev: {

  # claude-code — bumped ahead of nixpkgs (which lagged at 2.1.195). It's a
  # prebuilt-binary fetch, so overriding version + src is a clean targeted bump
  # that doesn't rebuild the world via a nixpkgs update. linux-x64 is fine: the
  # fleet is one x86_64 box now. Refresh the hash with:
  #   nix store prefetch-file https://downloads.claude.ai/claude-code-releases/<v>/linux-x64/claude
  claude-code = prev.claude-code.overrideAttrs (_old: {
    version = "2.1.293";
    src = prev.fetchurl {
      url = "https://downloads.claude.ai/claude-code-releases/2.1.293/linux-x64/claude";
      hash = "sha256-iWhAXibbR4r0TqvEY1q1ylVwV7cCpURgpZwT4bJT6Xg=";
    };
  });

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
