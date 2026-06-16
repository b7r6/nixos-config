# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                  // purescript-language-server // package
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Language Server Protocol server for PureScript, wrapping `purs ide server`.
# Not packaged in nixpkgs; built here from the published npm tarball.
#
# The tarball ships a pre-bundled `server.js` (esbuild output) that requires a
# handful of runtime deps as externals (shell-quote, uuid, vscode-*, which).
# We install those via buildNpmPackage using the committed package-lock.json,
# which keeps the build fully offline/pure.
#
# Regenerating the lockfile after a version bump:
#   tar xzf <npm-tarball> --strip-components=1
#   npm install --package-lock-only --omit=dev --ignore-scripts
#   cp package-lock.json modules/home/emacs/pkgs/purescript-language-server/

{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs,
  makeWrapper,
  purescript,
}:

let
  version = "0.18.5";
in
buildNpmPackage {
  pname = "purescript-language-server";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/purescript-language-server/-/purescript-language-server-${version}.tgz";
    hash = "sha256-K0pVq07nHdo/n+spBDfc8riwgzRMq4SQCJ1sqrEjNB0=";
  };

  # Lockfile generated from the tarball's own package.json (prod deps only).
  postPatch = ''
    cp ${./package-lock.json} ./package-lock.json
  '';

  # Hash of the npm dependency closure described by package-lock.json.
  npmDepsHash = "sha256-NUB47f/yFxrY//6QZ7o6UbaYnWrqjXYYR58MMJvxUC8=";

  # server.js is already bundled; nothing to compile.
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/purescript-language-server
    cp -r server.js package.json node_modules $out/lib/purescript-language-server/

    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/purescript-language-server \
      --add-flags "$out/lib/purescript-language-server/server.js" \
      --prefix PATH : ${lib.makeBinPath [ purescript ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Language Server Protocol server for PureScript";
    homepage = "https://github.com/nwolverson/purescript-language-server";
    license = licenses.mit;
    mainProgram = "purescript-language-server";
    platforms = platforms.all;
  };
}
