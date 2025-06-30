{ pkgs, lib }:
pkgs.stdenv.mkDerivation {
  pname = "berkeley-mono";
  version = "1.009";

  src = ./.;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/fonts/opentype
    cp $src/*.otf $out/share/fonts/opentype/

    runHook postInstall
  '';

  meta = with lib; {
    description = "Berkeley Mono typeface";
    license = licenses.unfree; # It's a commercial font
    platforms = platforms.all;
  };
}
