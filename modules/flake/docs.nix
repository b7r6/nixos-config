# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                  // hypermodern // nix // docs
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# mdBook documentation:
#   nix build .#docs        -> the rendered static site (docs/book → $out)
#   nix run   .#docs-serve  -> live-reloading preview server (mdbook serve)
#
# The source lives in docs/ (book.toml + src/). Keep this a pure derivation so
# the site is reproducible and CI-buildable.
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{
  perSystem = { pkgs, ... }: {
    packages.docs = pkgs.stdenvNoCC.mkDerivation {
      name = "hypermodern-docs";
      src = ../../docs;
      nativeBuildInputs = [ pkgs.mdbook ];
      buildPhase = ''
        runHook preBuild
        mdbook build --dest-dir ./book
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -r ./book/* $out/
        runHook postInstall
      '';
    };

    # `nix run .#docs-serve` — live preview at http://localhost:3000.
    apps.docs-serve = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "docs-serve";
          runtimeInputs = [
            pkgs.mdbook
            pkgs.git
          ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root/docs"
            echo "// hypermodern // docs // http://localhost:3000 (live reload)"
            exec mdbook serve --open --port 3000
          '';
        }
      );
    };
  };
}
