{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  name = "berkeley-mono-font";
  src = ./.;

  dontUnpack = true;
  installPhase = ''
    mkdir -p $out/share/fonts/opentype
    cp ./berkeley-mono/BerkeleyMono-SemiBold.otf $out/share/fonts/opentype/
  '';
}
