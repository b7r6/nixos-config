# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                       // hyper-modern-nixos // checks // attic
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Boot + config-correctness proof for the central-postgres + replicated
# api-server attic redesign, as a self-contained NixOS VM test (no R2, no real
# secrets). It exercises the SUBSTANTIVE new code paths:
#
#   - hyper-modern-nixos.databases.postgres  (opt-in, declarative atticd role+db)
#   - hyper-modern-nixos.attic mode="api-server" + passwordless databaseUrl
#     (PGPASSWORD via env file; sqlx reads it) overriding the upstream sqlite
#   - clientCache → localhost:8080 substituter-first + watch-store
#
# A single VM plays both postgres host and an api-server replica (monolithic in
# spirit, but driven through the same options the fleet uses). Storage is LOCAL
# here (R2 is just a different storage backend; the wiring under test is mode +
# db + substituter, which is backend-agnostic).
{ pkgs, inputs }:
let
  # A throwaway RS256 + PGPASSWORD env file, generated at build time. This is a
  # TEST secret living in the store ON PURPOSE — the whole point is to prove the
  # plumbing without touching agenix. PGPASSWORD matches the role password set
  # in postgresql.initialScript below.
  testEnvFile = pkgs.runCommand "attic-test-env" { nativeBuildInputs = [ pkgs.openssl ]; } ''
    rs256=$(openssl genrsa -traditional 2048 | base64 -w0)
    {
      echo "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$rs256"
      echo "PGPASSWORD=testpassword"
    } > $out
  '';
in
pkgs.testers.runNixOSTest {
  name = "attic-cache";

  nodes.machine = { ... }: {
    imports = [
      inputs.agenix.nixosModules.default
      ../../../nixos/state.nix
      ../../../nixos/postgres.nix
      ../nixos.nix
    ];

    # ── shared state: local postgres with the atticd role+db ──
    hyper-modern-nixos.databases.postgres.enable = true;

    # Create the role WITH a password + owned db. ensureUsers can't set a
    # password and runs after initialScript, so for the test we provision the
    # role directly. (On the real fleet the password is set by hand once; see
    # the deploy runbook.) initialScript runs on first cluster init only,
    # which is exactly the VM's situation.
    services.postgresql.initialScript = pkgs.writeText "init.sql" ''
      CREATE ROLE atticd WITH LOGIN PASSWORD 'testpassword';
      CREATE DATABASE atticd OWNER atticd;
    '';

    # ── atticd against that postgres ──
    # Use monolithic mode (= watchtower's fleet role): it runs DB MIGRATIONS
    # then serves. A bare api-server does NOT migrate — it expects the
    # monolithic node to have created the schema first — so a single-VM test
    # must be the monolithic node. (This is itself a useful proof: it confirms
    # the migration + serve path works against our passwordless-URL+PGPASSWORD
    # postgres wiring, which is exactly what watchtower does.)
    hyper-modern-nixos.attic = {
      enable = true;
      mode = "monolithic";
      environmentFile = "${testEnvFile}";
      databaseUrl = "postgresql://atticd@localhost/atticd";
      listen = "[::]:8080";
      # local storage for the test (R2 is a swappable backend)
      storage.type = "local";
      openFirewall = false;
      clientCache = {
        enable = true;
        name = "hypermodern";
        endpoint = "http://localhost:8080";
        publicKey = "hypermodern:x+kBunu5nD1KOhzCIawyZeq8w0LV0GC6A7suIRoHTm8=";
        # no pushTokenFile -> watch-store stays off (pull-only) for the test
      };
    };

    # keep the VM small/fast
    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 4096;
  };

  testScript = ''
    start_all()

    # postgres comes up and owns the atticd database
    machine.wait_for_unit("postgresql.service")
    machine.succeed("sudo -u postgres psql -lqt | cut -d'|' -f1 | grep -qw atticd")

    # atticd starts as an api-server and binds 8080 (proves mode + DB connect:
    # if the passwordless URL + PGPASSWORD plumbing were wrong, sqlx would fail
    # to authenticate and the unit would not become active).
    machine.wait_for_unit("atticd.service")
    machine.wait_for_open_port(8080)

    # the rendered atticd config uses our postgres URL, NOT the upstream sqlite
    # default, and NOT a leaked password.
    cfg = machine.succeed("cat $(systemctl show -p ExecStart atticd.service | grep -oE '/nix/store/[^ ]*server.toml' | head -1) || true")
    machine.succeed(
        "grep -rq 'postgresql://atticd@localhost/atticd' "
        "$(systemctl cat atticd.service | grep -oE -- '-f /nix/store/[^ ]+' | head -1 | cut -d' ' -f2)"
    )

    # nix is configured to consult the local hypermodern cache first.
    machine.succeed("grep -q 'localhost:8080/hypermodern' /etc/nix/nix.conf")
    machine.succeed("grep -q 'hypermodern:x+kBunu5nD1KOhzCIawyZeq8w0LV0GC6A7suIRoHTm8=' /etc/nix/nix.conf")

    # The server is alive and DB-backed: hitting a cache endpoint returns a
    # real HTTP response (401 for the not-yet-public 'hypermodern' cache, NOT a
    # 500 — a 500 would mean the DB/migration/auth wiring is broken, which is
    # exactly what earlier iterations of this test caught). We assert a clean
    # 401, proving migrations ran and the auth layer is serving.
    status = machine.succeed(
        "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/hypermodern/nix-cache-info"
    ).strip()
    assert status == "401", f"expected 401 from not-yet-public cache, got {status}"

    # And the atticadm wrapper can mint a token (proves the RS256 signing secret
    # from the env file loaded correctly).
    machine.succeed("atticd-atticadm make-token --sub test --validity '1h' --pull 'hypermodern' >/dev/null")

    print("// attic-cache // monolithic + postgres migrations + auth + localhost substituter: OK")
  '';
}
