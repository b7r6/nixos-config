# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                      // hyper-modern-nixos // checks // backup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Proof that the restic→S3(R2) backup mechanism is SOUND, as a self-contained
# NixOS VM test. R2 is S3-compatible, so a local minio stands in for it — the
# code path under test (services.restic via hyper-modern-nixos.backup +
# RESTIC_REPOSITORY from the env file + password file) is identical.
#
# It proves the FULL round trip end-to-end:
#   1. minio (S3) up + bucket created
#   2. manual `restic init` (the module sets initialize=false by design)
#   3. seed real + excluded data, run the systemd backup unit
#   4. a snapshot exists; prune + check (the module's --read-data-subset) ran
#   5. RESTORE the data to a clean dir and byte-compare (integrity round trip)
#   6. excludes actually bite (a *.safetensors is NOT in the snapshot)
{ pkgs }:
let
  testPassword = "correct-horse-battery-staple";
  accessKey = "testaccesskey";
  secretKey = "testsecretkey123";
  bucket = "backups-restic";

  # The agenix env file the module reads (RESTIC_REPOSITORY + S3 creds). A
  # build-time TEST file in the store on purpose — proving plumbing, not secrecy.
  testEnvFile = pkgs.writeText "restic-test-env" ''
    RESTIC_REPOSITORY=s3:http://127.0.0.1:9000/${bucket}/testhost
    AWS_ACCESS_KEY_ID=${accessKey}
    AWS_SECRET_ACCESS_KEY=${secretKey}
    AWS_DEFAULT_REGION=us-east-1
  '';

  testPasswordFile = pkgs.writeText "restic-test-password" testPassword;

  minioCreds = pkgs.writeText "minio-creds" ''
    MINIO_ROOT_USER=${accessKey}
    MINIO_ROOT_PASSWORD=${secretKey}
  '';
in
pkgs.testers.runNixOSTest {
  name = "backup-restic";

  # minio is an S3-compatible stand-in for R2. nixpkgs flags the current minio
  # as insecure; permit it for the test's node pkgs ONLY (a throwaway VM, never
  # the fleet). Set at the test level so it's the single source of node pkgs and
  # there's no module-vs-framework priority conflict. The restic→S3 path under
  # test is unaffected by minio's advisory flag.
  node.pkgs = pkgs.lib.mkForce (
    import pkgs.path {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.permittedInsecurePackages = [ "minio-2025-10-15T17-29-55Z" ];
    }
  );

  nodes.machine = { pkgs, ... }: {
    imports = [ ../modules/nixos/backup.nix ];

    # local S3 (stand-in for R2)
    services.minio = {
      enable = true;
      rootCredentialsFile = minioCreds;
    };

    environment.systemPackages = [
      pkgs.restic
      pkgs.minio-client
      pkgs.awscli2
    ];

    hyper-modern-nixos.backup = {
      enable = true;
      passwordFile = "${testPasswordFile}";
      environmentFile = "${testEnvFile}";
      paths = [ "/var/data" ];
      # keep the test fast/deterministic: no randomized timer delay needed,
      # we trigger the unit directly.
    };

    virtualisation.memorySize = 2048;
    virtualisation.diskSize = 4096;
  };

  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("minio.service")
    machine.wait_for_open_port(9000)

    # ── create the bucket (mc against local minio) ──
    machine.succeed(
        "mc alias set local http://127.0.0.1:9000 ${accessKey} ${secretKey}"
    )
    machine.succeed("mc mb local/${bucket}")

    # ── seed real data + an excluded weight file ──
    machine.succeed("mkdir -p /var/data")
    machine.succeed("echo 'irreplaceable-secret-data' > /var/data/important.txt")
    machine.succeed("head -c 4096 /dev/urandom > /var/data/blob.bin")
    machine.succeed("echo 'should-be-excluded' > /var/data/model.safetensors")

    # ── the module sets initialize=false: init BY HAND (mirrors the runbook) ──
    init = (
        "set -a; . ${testEnvFile}; set +a; "
        "RESTIC_PASSWORD_FILE=${testPasswordFile} restic init"
    )
    machine.succeed(init)

    # ── run the systemd backup unit the module generated ──
    machine.succeed("systemctl start restic-backups-system.service")
    # oneshot: must have finished successfully
    machine.succeed("systemctl is-active restic-backups-system.service || true")
    res = machine.succeed(
        "systemctl show -p Result --value restic-backups-system.service"
    ).strip()
    assert res == "success", f"backup unit Result={res!r} (expected success)"

    # ── a snapshot exists ──
    env = "set -a; . ${testEnvFile}; set +a; RESTIC_PASSWORD_FILE=${testPasswordFile} "
    snaps = json.loads(machine.succeed(env + "restic snapshots --json"))
    assert len(snaps) >= 1, f"expected >=1 snapshot, got {len(snaps)}"

    # ── excludes bite: model.safetensors must NOT be in the snapshot ──
    listing = machine.succeed(env + "restic ls latest")
    assert "important.txt" in listing, "important.txt missing from snapshot!"
    assert "blob.bin" in listing, "blob.bin missing from snapshot!"
    assert "model.safetensors" not in listing, "excluded *.safetensors got backed up!"

    # ── repo integrity check (the module runs --read-data-subset post-backup) ──
    machine.succeed(env + "restic check --read-data-subset=100%")

    # ── RESTORE round trip: pull data back to a clean dir, byte-compare ──
    machine.succeed(env + "restic restore latest --target /restored")
    machine.succeed("cmp /var/data/important.txt /restored/var/data/important.txt")
    machine.succeed("cmp /var/data/blob.bin /restored/var/data/blob.bin")
    machine.succeed("test ! -e /restored/var/data/model.safetensors")

    print("// backup-restic // init + backup + snapshot + excludes + check + restore: OK")
  '';
}
