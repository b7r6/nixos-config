# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // ono-sendai-generator // package
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Lean4-based theme generator for the Ono-Sendai / Maas color system.
# Generates editor themes (Emacs, Neovim, VSCode), palette JSON for Nix,
# and the conformance vectors every reimplementation is pinned against.
#
# Usage:
#   ono-sendai-gen json [level] [hero] [axis]              — dark palette JSON
#   ono-sendai-gen json-light [level] [hero] [axis] [ramp] — maas (light) palette
#   ono-sendai-gen json-all [hero] [axis]                  — all levels, both polarities
#   ono-sendai-gen vectors                                 — conformance vectors
#   ono-sendai-gen emacs [level] [hero] [axis]             — Emacs theme

{
  lib,
  stdenv,
  lean4,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "ono-sendai-generator";
  version = "2.0.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      let
        base = baseNameOf path;
      in
      base != ".lake" && base != "out";
  };

  nativeBuildInputs = [
    lean4
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    lake build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp .lake/build/bin/ono-sendai-gen $out/bin/

    makeWrapper $out/bin/ono-sendai-gen $out/bin/ono-sendai-json \
      --add-flags "json"

    makeWrapper $out/bin/ono-sendai-gen $out/bin/ono-sendai-emacs \
      --add-flags "emacs"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Ono-Sendai / Maas base16 theme generator (Lean4)";
    homepage = "https://github.com/straylight-software/ono-sendai";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.all;
  };
}
