{ pkgs, lib, ... }:
pkgs.stdenv.mkDerivation {
  pname = "berkeley-mono-font";
  version = "0.1.336";
  src = ./.;

  dontUnpack = true;
  installPhase = ''
    export DEST_DIR=$out/share/fonts/opentype
    mkdir -p $DEST_DIR

    for f in $src/*.otf; do
      echo "copying $f to $DEST_DIR..."
      cp $f $DEST_DIR/
    done
  '';
}
