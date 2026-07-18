# Azonix — bold geometric uppercase display font (cherry-picked from the
# new-suzuki branch). Free for personal use (not OFL), so it is vendored as
# a binary OTF rather than pulled from nixpkgs. n.b. uppercase-only: fine
# for the bar, hostile to body text.
{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "azonix-font";
  version = "1.0";

  src = ./Azonix.otf;

  dontUnpack = true;
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/fonts/opentype
    cp $src $out/share/fonts/opentype/Azonix.otf
    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Azonix — bold geometric sans-serif display typeface";
    homepage = "https://www.dafont.com/azonix.font";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}
