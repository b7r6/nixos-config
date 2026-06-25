# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // packages // supabase-postgres-meta
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# RESTful API for managing Postgres (Studio's backend). Simple Node.js app with
# no native deps that matter for our use case (we disable Sentry profiling).
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
  runtimeShell,
}:

buildNpmPackage rec {
  pname = "supabase-postgres-meta";
  version = "0.96.6";

  src = fetchFromGitHub {
    owner = "supabase";
    repo = "postgres-meta";
    rev = "v${version}";
    hash = "sha256-scDgUyu4/AaBCkfOXn8lyetEq6dIaXGaQCbNy53y/j0=";
  };

  nodejs = nodejs_22;
  npmDepsHash = "sha256-vvkeAZ5bQfdT1y2by45vIys6AAnQelABsiipzEl+iZE=";

  # skip the native sentry profiling addon build (we don't need it)
  npmFlags = [ "--ignore-scripts" ];
  makeCacheWritable = true;

  # the build script expects cpy-cli (devDep) — it's installed since we don't
  # prune before building. tsc + cpy emits to dist/.
  npmBuildScript = "build";

  # after build, remove devDeps to shrink the closure
  postBuild = ''
    npm prune --omit=dev
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/postgres-meta
    cp -r dist $out/lib/postgres-meta/
    cp -r node_modules $out/lib/postgres-meta/
    cp package.json $out/lib/postgres-meta/

    mkdir -p $out/bin
    cat > $out/bin/postgres-meta <<EOF
    #!${runtimeShell}
    exec ${nodejs_22}/bin/node "$out/lib/postgres-meta/dist/server/server.js" "\$@"
    EOF
    chmod +x $out/bin/postgres-meta

    runHook postInstall
  '';

  meta = with lib; {
    description = "RESTful API for managing Postgres (Supabase Studio backend)";
    homepage = "https://github.com/supabase/postgres-meta";
    license = licenses.mit;
    mainProgram = "postgres-meta";
  };
}
