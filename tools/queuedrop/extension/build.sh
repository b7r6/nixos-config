#!/usr/bin/env bash
# Build the queuedrop MV3 extension: compile PureScript, bundle three entry
# points with esbuild (injecting webextension-polyfill), emit dist/.
#
# Run inside a shell that has: purs, spago, node, esbuild, and the npm dep
# `webextension-polyfill` resolvable (see flake.nix / nix-shell wrapper).
set -euo pipefail
cd "$(dirname "$0")"

OUT=dist
mkdir -p "$OUT"

echo "==> spago build (PureScript -> output/)"
spago build

# esbuild bundles each PS entry module's compiled JS. PureScript emits ES
# modules under output/<Module>/index.js exporting `main`. We write a tiny
# entry shim per surface that imports and runs main, then esbuild bundles it
# (resolving webextension-polyfill from node_modules).
bundle() {
  local module="$1" out="$2"
  local shim
  # shim lives in the project dir (not /tmp) so its relative import resolves
  shim="entry-${module}.js"
  cat >"$shim" <<EOF
import { main } from "./output/${module}/index.js";
main();
EOF
  esbuild "$shim" \
    --bundle --format=esm --platform=browser --target=es2020 \
    --outfile="${OUT}/${out}" \
    --log-level=warning
  rm -f "$shim"
  echo "    bundled ${module} -> ${OUT}/${out}"
}

echo "==> esbuild bundles"
bundle Background background.js
bundle Content content.js
bundle Options options.js

echo "==> static assets"
cp static/manifest.json "$OUT/"
cp static/options.html "$OUT/"
cp static/icon-16.png static/icon-32.png static/icon-48.png static/icon-128.png "$OUT/"

echo "==> done: $OUT/"
ls -la "$OUT/"
