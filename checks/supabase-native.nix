# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hyper-modern-nixos // checks // supabase-native
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Integration test for the native Supabase stack. Boots a VM with the full
# supabase-native module and verifies:
#
#   1. PG17 cluster initializes and serves on port 5433
#   2. Init SQL applies (roles + schema exist)
#   3. GoTrue starts and /health returns 200
#   4. PostgREST starts and accepts connections
#   5. The nginx gateway routes /auth/v1/ and /rest/v1/ correctly
#   6. postgres-meta responds on its port
#
# This exercises the entire boot-order dependency chain: env-split → db init →
# service startup → gateway routing. The crane-extracted services (realtime,
# storage, studio) are included but may time out on first build in CI due to
# the multi-GB image pulls — the core assertions above are the load-bearing ones.
#
# Run: nix build .#checks.x86_64-linux.supabase-native
{ pkgs, inputs }:
let
  inherit (inputs) self;

  # fake secret bundle for the test (never leaves the VM)
  testEnvFile = pkgs.writeText "supabase-env-test" ''
    JWT_SECRET=super-secret-jwt-token-with-at-least-32-characters-long-for-hs256
    ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlhdCI6MTYxNDIxNDIwMCwiZXhwIjoxOTI5NTkwMjAwfQ.a_fake_signature_for_testing_only
    SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaWF0IjoxNjE0MjE0MjAwLCJleHAiOjE5Mjk1OTAyMDB9.a_fake_signature_for_testing_only
    POSTGRES_PASSWORD=testpassword123
    SECRET_KEY_BASE=supersecretkeythatisatleast64characterslongsupersecretkeythatisatleast
    VAULT_ENC_KEY=0000000000000000000000000000000000000000000000000000000000000000
    PG_META_CRYPTO_KEY=0000000000000000000000000000000000000000000000000000000000000000
    DASHBOARD_USERNAME=admin
    DASHBOARD_PASSWORD=admin
  '';
in
pkgs.testers.runNixOSTest {
  name = "supabase-native";

  nodes.supabase = { ... }: {
    imports = [
      ../modules/nixos/supabase-native.nix
      ../modules/nixos/state.nix
      ../modules/nixos/network.nix
      inputs.agenix.nixosModules.default
    ];

    _module.args.flake = {
      inherit self inputs;
      config = { };
    };

    hyper-modern-nixos.supabase-native = {
      enable = true;
      publicUrl = "http://localhost:8000";
      # point at our test secret file directly (bypass agenix in the VM)
      environmentFile = toString testEnvFile;
      selfWireSecret = false;
    };

    # network module needed for the firewall option surface
    hyper-modern-nixos.network.enable = true;

    # the test VM doesn't have agenix — secrets are faked above
    # also disable the state module's backup assertion
    hyper-modern-nixos.state.dirs = { };

    virtualisation.memorySize = 4096;
    virtualisation.diskSize = 8192;

    # allow more time for PG init + migrations
    systemd.services.supabase-db.serviceConfig.TimeoutStartSec = "120s";
    systemd.services.supabase-db-init-sql.serviceConfig.TimeoutStartSec = "120s";
  };

  testScript = ''
    import json

    start_all()

    # ── 1. database cluster boots ─────────────────────────────────────────────
    supabase.wait_for_unit("supabase-db.service", timeout=120)
    supabase.wait_for_open_port(5433, timeout=60)
    print("// supabase-db // cluster running on port 5433")

    # ── 2. init SQL applies (roles exist) ─────────────────────────────────────
    supabase.wait_for_unit("supabase-db-init-sql.service", timeout=120)
    roles = supabase.succeed(
        "sudo -u supabase-postgres psql -h /run/supabase-db -p 5433 -U postgres -d postgres "
        "-t -c \"SELECT rolname FROM pg_roles WHERE rolname LIKE 'supabase_%' ORDER BY 1;\""
    ).strip()
    assert "supabase_admin" in roles, f"missing supabase_admin role: {roles}"
    assert "supabase_auth_admin" in roles, f"missing supabase_auth_admin role: {roles}"
    assert "supabase_storage_admin" in roles, f"missing supabase_storage_admin role: {roles}"
    print(f"// supabase-db-init-sql // roles present: {roles.split()}")

    # verify the authenticator role (used by PostgREST)
    auth_role = supabase.succeed(
        "sudo -u supabase-postgres psql -h /run/supabase-db -p 5433 -U postgres -d postgres "
        "-t -c \"SELECT 1 FROM pg_roles WHERE rolname = 'authenticator';\""
    ).strip()
    assert "1" in auth_role, "authenticator role missing"
    print("// supabase-db-init-sql // authenticator role confirmed")

    # ── 3. GoTrue (auth) health ───────────────────────────────────────────────
    supabase.wait_for_unit("supabase-auth.service", timeout=90)
    supabase.wait_for_open_port(9999, timeout=30)
    auth_health = supabase.succeed("curl -sf http://127.0.0.1:9999/health")
    print(f"// supabase-auth // healthy: {auth_health.strip()}")

    # ── 4. PostgREST readiness ────────────────────────────────────────────────
    supabase.wait_for_unit("supabase-rest.service", timeout=90)
    supabase.wait_for_open_port(3000, timeout=30)
    # PostgREST admin endpoint (port 3001) returns readiness
    rest_ready = supabase.succeed("curl -sf http://127.0.0.1:3001/ready")
    print(f"// supabase-rest // ready: {rest_ready.strip()}")

    # ── 5. nginx gateway routing ──────────────────────────────────────────────
    supabase.wait_for_unit("nginx.service", timeout=30)
    supabase.wait_for_open_port(8000, timeout=10)

    # /auth/v1/health through the gateway
    gw_auth = supabase.succeed("curl -sf http://127.0.0.1:8000/auth/v1/health")
    print(f"// gateway // /auth/v1/health: {gw_auth.strip()}")

    # /rest/v1/ through the gateway (should return PostgREST's schema response
    # or 401 without a valid JWT — either means it's routing correctly)
    gw_rest_code = supabase.succeed(
        "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8000/rest/v1/"
    ).strip()
    assert gw_rest_code in ("200", "401"), f"gateway /rest/v1/ unexpected: {gw_rest_code}"
    print(f"// gateway // /rest/v1/ status: {gw_rest_code}")

    # ── 6. postgres-meta responds ─────────────────────────────────────────────
    supabase.wait_for_unit("supabase-meta.service", timeout=60)
    supabase.wait_for_open_port(8085, timeout=30)
    meta_health = supabase.succeed(
        "curl -sf http://127.0.0.1:8085/health"
    )
    print(f"// supabase-meta // healthy: {meta_health.strip()}")

    # ── 7. imgproxy responds ──────────────────────────────────────────────────
    supabase.wait_for_unit("supabase-imgproxy.service", timeout=30)
    supabase.wait_for_open_port(5001, timeout=10)
    imgproxy_health = supabase.succeed(
        "curl -sf http://127.0.0.1:5001/health"
    )
    print(f"// supabase-imgproxy // healthy: {imgproxy_health.strip()}")

    print("")
    print("// supabase-native // all core services: PASS")
  '';
}
