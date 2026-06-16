# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                  // purs-tidy // package
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# A syntax tidy-upper (formatter) for PureScript.
# Not packaged in nixpkgs; built here from the published npm tarball.
#
# purs-tidy is a PureScript program compiled to a self-contained, pre-bundled
# ES module with zero runtime npm dependencies, so we just unpack the tarball
# and wrap bin/index.js with node — no npm/buildNpmPackage required.

{
  lib,
  stdenvNoCC,
  fetchurl,
  nodejs,
  makeWrapper,
}:

let
  version = "0.11.1";
in
stdenvNoCC.mkDerivation {
  pname = "purs-tidy";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/purs-tidy/-/purs-tidy-${version}.tgz";
    hash = "sha256-+bX+NntwZw7YYgO1kkSGSLnpXb8imgPB2QCjRH6hsoE=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/purs-tidy
    cp -r bin bundle package.json $out/lib/purs-tidy/

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/purs-tidy \
      --add-flags "$out/lib/purs-tidy/bin/index.js"

    runHook postInstall
  '';

  meta = with lib; {
    description = "A syntax tidy-upper (formatter) for PureScript";
    homepage = "https://github.com/natefaubion/purescript-tidy";
    license = licenses.mit;
    mainProgram = "purs-tidy";
    platforms = platforms.all;
  };
}
