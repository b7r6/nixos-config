{
  description = "Ono-Sendai Color Theme System - Lean-based generator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      perSystem =
        {
          config,
          pkgs,
          system,
          ...
        }:
        {
          # Lean toolchain via elan
          _module.args.pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (_final: prev: {
                elan = prev.elan.overrideAttrs (_old: {
                  # Ensure we have the latest elan
                  version = "3.0.0";
                });
              })
            ];
          };

          # The theme generator package
          packages.ono-sendai-generator = pkgs.stdenv.mkDerivation {
            pname = "ono-sendai-generator";
            version = "1.0.0";

            src = ./lean;

            nativeBuildInputs = [ pkgs.elan ];

            buildPhase = ''
              export HOME=$TMPDIR
              elan default stable
              lake build
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp .lake/build/bin/ono-sendai-gen $out/bin/

              # Create wrapper script that generates themes
              cat > $out/bin/generate-ono-sendai-themes << 'EOF'
              #!/usr/bin/env bash
              set -e

              OUT_DIR="''${1:-./out}"
              mkdir -p "$OUT_DIR"

              echo "// ono-sendai // generating themes //"

              # Generate all editor themes
              ono-sendai-gen emacs   > "$OUT_DIR/ono-sendai-theme.el"
              ono-sendai-gen nvim    > "$OUT_DIR/ono-sendai.lua"
              ono-sendai-gen vscode  > "$OUT_DIR/ono-sendai-vscode.json"

              echo "// done // output in $OUT_DIR //"
              EOF
              chmod +x $out/bin/generate-ono-sendai-themes
            '';
          };

          # Default package
          packages.default = config.packages.ono-sendai-generator;

          # Development shell with Lean toolchain
          devShells.default = pkgs.mkShell {
            name = "ono-sendai-dev";

            inputsFrom = [ config.packages.ono-sendai-generator ];

            buildInputs = with pkgs; [
              elan
              git
              # Editor support
              # emacs
              # neovim
              # vscode
            ];

            shellHook = ''
              echo "// ono-sendai // development shell //"
              echo ""
              echo "Available commands:"
              echo "  lake build          - Build the generator"
              echo "  lake run            - Run the generator"
              echo "  elan default stable - Set Lean toolchain"
              echo ""
              echo "To generate themes:"
              echo "  lake run > themes.json"
            '';
          };

          # Formatter
          formatter = pkgs.nixfmt;
        };
    };
}
