# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // ono-sendai-generator // package
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Lean4-based theme generator for the Ono-Sendai color system.
# Generates editor themes (Emacs, Neovim, VSCode) from HSL parameters.
#
# Usage:
#   ono-sendai-gen json [level] [hero] [axis]   — JSON palette for Nix
#   ono-sendai-gen emacs [level] [hero] [axis]  — Emacs theme
#   ono-sendai-gen nvim-palette                 — Neovim palette.lua
#   ono-sendai-gen nvim-init                    — Neovim init.lua

{
  lib,
  stdenv,
  elan,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "ono-sendai-generator";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [
    elan
    makeWrapper
  ];

  # Lean needs network access during build to download mathlib cache
  # For now, we'll build without network and accept slower build
  buildPhase = ''
    export HOME=$TMPDIR
    export ELAN_HOME=$TMPDIR/.elan

    # Initialize elan and install stable toolchain
    elan default stable

    # Build with lake
    lake build
  '';

  installPhase = ''
    mkdir -p $out/bin

    # Install the built binary
    cp .lake/build/bin/ono-sendai-gen $out/bin/

    # Create convenience wrappers for common operations
    makeWrapper $out/bin/ono-sendai-gen $out/bin/ono-sendai-json \
      --add-flags "json"

    makeWrapper $out/bin/ono-sendai-gen $out/bin/ono-sendai-emacs \
      --add-flags "emacs"
  '';

  meta = with lib; {
    description = "Ono-Sendai base16 theme generator (Lean4)";
    homepage = "https://github.com/straylight-software/ono-sendai";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.all;
  };
}
