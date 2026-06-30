# Azonix — bold geometric uppercase display font
# Free for personal use (not OFL). Vendored as a binary font package.
{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "azonix-font";
  version = "1.0";

  src = ./assets/Azonix.otf;

  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/fonts/truetype
    cp $src $out/share/fonts/truetype/Azonix.otf
    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Azonix — bold geometric sans-serif display typeface";
    homepage = "https://www.dafont.com/azonix.font";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
