# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                           // packages // supabase-studio
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Supabase Studio (Next.js dashboard) built from our fork. Produces a standalone
# Next.js output that runs with `node apps/studio/server.js`.
#
# Build strategy:
#   1. FOD phase: `pnpm fetch` populates a content-addressed store from the
#      lockfile (network access allowed).
#   2. Build phase (sandboxed, no network): `pnpm install --offline` from the
#      pre-fetched store, then `turbo run build --filter=studio` which builds
#      all workspace deps in topological order.
#
# Corepack/self-management bypass: nixpkgs pnpm (10.34) is on PATH; we patch
# .npmrc and package.json so pnpm never tries to download a different version
# or enforce engine constraints.
{
  lib,
  stdenvNoCC,
  stdenv,
  fetchFromGitHub,
  nodejs_22,
  pnpm_10,
  python3,
  pkg-config,
  vips,
  git,
  cacert,
  jq,
  makeWrapper,
}:
let
  src = fetchFromGitHub {
    owner = "sensenet-ai";
    repo = "supabase";
    rev = "bf1c1b47808986597b3619bc2743d2b359d4f8e8";
    hash = "sha256-AoXwnWVdO9xFZs0OWM8eCJDrgAEVYS/lJ4/+0IccWyk=";
  };

  # common env vars to neutralize corepack and pnpm self-management
  corepackEnv = {
    COREPACK_ENABLE_NETWORK = "0";
    COREPACK_ENABLE_STRICT = "0";
    COREPACK_ENABLE_DOWNLOAD = "0";
    # pnpm 10+ has its own package manager version management — disable it
    # (it sees "packageManager": "pnpm@10.24.0" and tries to download that)
    PNPM_MANAGE_PACKAGE_MANAGER_VERSIONS = "false";
    # tell pnpm not to check engine compatibility (our node/pnpm are fine)
    npm_config_engine_strict = "false";
  };

  # FOD: fetch pnpm store (all deps). This runs with network access and is
  # content-addressed by the output hash. `pnpm fetch` populates the store
  # from pnpm-lock.yaml without needing the full source tree.
  pnpmStore = stdenvNoCC.mkDerivation (
    corepackEnv
    // {
      name = "supabase-studio-pnpm-store";
      inherit src;

      nativeBuildInputs = [
        nodejs_22
        pnpm_10
        git
        cacert
        python3
        pkg-config
        jq
      ];
      buildInputs = [ vips ];

      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
      outputHash = "sha256-AsYctiJ7Ho8EW0uT8HdwNIbMfirc7XZuG2dn2sFoAPA=";

      SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";

      buildPhase = ''
        export HOME=$TMPDIR

        # disable pnpm self-management (it tries to download pnpm@10.24.0)
        echo "manage-package-manager-versions=false" >> .npmrc

        # remove the preinstall hook that runs `npx only-allow pnpm` (needs network)
        jq 'del(.scripts.preinstall)' package.json > package.json.tmp
        mv package.json.tmp package.json

        # pnpm fetch downloads all deps from the lockfile into the store
        pnpm fetch --store-dir=$out
      '';

      dontInstall = true;
      dontFixup = true;
    }
  );
in
stdenv.mkDerivation (
  corepackEnv
  // {
    pname = "supabase-studio";
    version = "2026.06.25-sensenet";
    inherit src;

    nativeBuildInputs = [
      nodejs_22
      pnpm_10
      python3
      pkg-config
      git
      jq
      makeWrapper
    ];
    buildInputs = [ vips ];

    # pnpm hoisted symlinks may dangle in standalone output — harmless
    dontCheckForBrokenSymlinks = true;

    # next.js telemetry and turbo telemetry off
    NEXT_TELEMETRY_DISABLED = "1";
    TURBO_TELEMETRY_DISABLED = "1";
    DO_NOT_TRACK = "1";
    SKIP_ASSET_UPLOAD = "1";

    # studio build-time env
    NEXT_PUBLIC_STUDIO_VERSION = "2026.06.25-sensenet";

    buildPhase = ''
      export HOME=$TMPDIR

      # disable pnpm self-management and engine-strict
      echo "manage-package-manager-versions=false" >> .npmrc
      echo "engine-strict=false" >> .npmrc

      # patch package.json: remove engines.pnpm constraint, fix packageManager to
      # our actual version so turbo can resolve workspaces, remove preinstall hook
      jq --arg ver "${pnpm_10.version}" '
        del(.scripts.preinstall) |
        del(.engines.pnpm) |
        .packageManager = "pnpm@\($ver)"
      ' package.json > package.json.tmp
      mv package.json.tmp package.json

      # strip preinstall hooks from workspace packages (they run npx)
      for f in apps/*/package.json packages/*/package.json; do
        if [ -f "$f" ] && jq -e '.scripts.preinstall' "$f" > /dev/null 2>&1; then
          jq 'del(.scripts.preinstall)' "$f" > "$f.tmp"
          mv "$f.tmp" "$f"
        fi
      done

      # pnpm 10 writes project metadata into the store — copy to writable location
      export STORE=$TMPDIR/pnpm-store
      cp -a ${pnpmStore} $STORE
      chmod -R u+w $STORE

      # install from the pre-fetched store (offline, skip lifecycle scripts)
      pnpm install \
        --frozen-lockfile \
        --offline \
        --store-dir=$STORE \
        --ignore-scripts

      # patch the build:next script to skip asset upload (uses /bin/bash shebang)
      jq '.scripts["build:next"] = "next build"' apps/studio/package.json > apps/studio/package.json.tmp
      mv apps/studio/package.json.tmp apps/studio/package.json

      # run native addon build scripts, but skip the supabase CLI package
      # (its postinstall downloads a binary from the internet)
      pnpm rebuild --filter "!supabase"

      # build studio + all its workspace deps via turbo
      pnpm turbo run build --filter=studio
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/app

      # standalone output (next.js copies node_modules + server into here)
      cp -r apps/studio/.next/standalone/* $out/app/

      # static assets (next.js expects these alongside the standalone server)
      mkdir -p $out/app/apps/studio/.next/static
      cp -r apps/studio/.next/static/* $out/app/apps/studio/.next/static/

      # public dir
      if [ -d apps/studio/public ]; then
        cp -r apps/studio/public $out/app/apps/studio/public
      fi

      # wrapper script
      mkdir -p $out/bin
      makeWrapper ${nodejs_22}/bin/node $out/bin/supabase-studio \
        --add-flags "$out/app/apps/studio/server.js"

      runHook postInstall
    '';

    meta = {
      description = "Supabase Studio (sensenet-ai fork with multi-db picker)";
      homepage = "https://github.com/sensenet-ai/supabase";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  }
)
