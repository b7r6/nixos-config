# NieR-Cursors — XCursor theme based on NieR Automata
# MIT licensed, vendored from github:Beinsezii/NieR-Cursors
{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "nier-cursors";
  version = "2020-08-25";

  src = pkgs.fetchurl {
    url = "https://github.com/Beinsezii/NieR-Cursors/releases/download/2020-08-25/NieR_Cursors_2020-08-25.tar.xz";
    sha256 = "097kj99a16f60fzzh9k94lgjkvj3i1awgpgxwmyf43l71zy1ysaa";
  };

  sourceRoot = "nier_cursors";

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/icons/NieR_Cursors
    cp -r * $out/share/icons/NieR_Cursors/
    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "XCursor theme based on NieR Automata";
    homepage = "https://github.com/Beinsezii/NieR-Cursors";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
