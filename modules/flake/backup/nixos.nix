# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                 // hyper-modern-nixos // flake // backup/nixos
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# restic-based backups, OFF BY DEFAULT.
#
# Philosophy (per the runbook in README.md): do the FIRST backup BY HAND so you
# can verify the repo, retention, and restore path before any timer touches your
# data. Once you trust it, flip `enable = true` and the systemd timer takes over
# the exact same repo with the exact same settings.
#
# Secrets: the restic repository password comes from an agenix secret
# (restic-password.<host>.age), never from the nix store. The repo URL and any
# backend credentials (S3/B2/etc.) come from an agenix environment file. Nothing
# here is enabled until you opt a host in, so this module is inert by default and
# cannot brick a box.
#
# Manual first run (see README.md for the full runbook), e.g. for a local repo:
#   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
#     restic -r /path/to/repo init
#   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
#     restic -r /path/to/repo backup /home /etc /var/lib
#   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
#     restic -r /path/to/repo snapshots          # verify
# then set hyper-modern-nixos.backup.enable = true and rebuild.

{
  config,
  lib,
  pkgs,
  # `flake` comes from specialArgs on real hosts. Defaulted to null so contexts
  # that import this module without it (e.g. an isolated nixosTest that wires its
  # own secret paths and sets passwordSecret/environmentSecret = null) still
  # evaluate — machineSecrets is only forced when a secret name is non-null.
  flake ? null,
  ...
}:
let
  cfg = config.hyper-modern-nixos.backup;
  machineSecrets = flake.self + "/secrets/agenix/machines";
in
{
  options.hyper-modern-nixos.backup = {
    enable = lib.mkEnableOption "restic backups (off by default; do the first run by hand)";

    # ── Self-wired agenix secrets (by name) ─────────────────────────────────────
    # When set, the module wires age.secrets.<name>.file itself (from the repo)
    # and derives the runtime path, so a host only sets enable + paths. The R2
    # env secret is PER-HOST (restic-r2-env.<host>.age), hence configurable.
    passwordSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "restic-password";
      description = "agenix secret NAME for the repo passphrase (null = wire passwordFile yourself).";
    };

    environmentSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "restic-r2-env.watchtower";
      description = "agenix secret NAME for the R2 env file (null = wire environmentFile yourself).";
    };

    repository = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "/srv/backup/restic or s3:https://… or b2:bucket:path";
      description = ''
        restic repository location. Local path, rest-server URL, or a cloud
        backend (s3:/b2:/etc.). For cloud backends, supply credentials via
        {option}`environmentFile`.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix/${cfg.passwordSecret}";
      defaultText = "/run/agenix/\${passwordSecret}";
      description = ''
        Runtime path to the repo password file. Defaults to the agenix runtime
        path derived from passwordSecret (which the module also wires). NEVER a
        store path.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = if cfg.environmentSecret != null then "/run/agenix/${cfg.environmentSecret}" else null;
      defaultText = "/run/agenix/\${environmentSecret} (or null)";
      description = ''
        Optional path to an env file with backend credentials (e.g.
        AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, B2_ACCOUNT_ID / B2_ACCOUNT_KEY).
        Should be an agenix secret path, not a store path.

        Fleet scoping convention: ONE R2 bucket, ONE repo PER MACHINE under a
        per-host prefix. The repo URL lives in this env file as
          RESTIC_REPOSITORY=s3:https://<acct>.r2.cloudflarestorage.com/<bucket>/<hostname>
        so the account id stays out of the nix store and each host gets an
        isolated repo (no shared locks, independent retention) while sharing
        the same bucket and R2 token. Leave `repository` empty in that case.
      '';
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/home"
        "/etc"
        "/var/lib"
      ];
      description = "Paths to back up.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # ── caches: re-downloadable, never worth a cent of R2 ──────────────
        "/home/*/.cache" # HF hub, uv, pip, bun, cabal, bazel, whisper, …
        "/home/*/.local/share/Trash"
        "/home/*/.local/state/nix"

        # tool data/state that is a re-fetchable mirror, NOT in ~/.cache
        "/home/*/.local/share/uv" # uv's managed pythons + wheel cache
        "/home/*/.local/share/pnpm" # pnpm content-addressable store
        "/home/*/.local/share/virtualenvs"
        "/home/*/.npm"
        "/home/*/.cargo/registry" # crates.io download cache (not your code)
        "/home/*/.rustup" # re-installable toolchains
        "/home/*/.ollama/models" # re-pullable model blobs
        "/home/*/.nix-defexpr"

        # ── ML/model weights: disposable everywhere ───────────────────────
        # No important training happened on these machines, so model weights
        # anywhere in the tree are re-fetchable/regenerable and never worth R2
        # storage — including weight files checked into src/data/archive dirs
        # (~100GB+ of them) and self-produced quantization output (.pt/.pth).
        # Excluded by EXTENSION so they're dropped wherever they live; this is
        # deliberately blanket. If a future host DOES do real training, override
        # `exclude` there to keep its run outputs.
        "/home/*/models" # ComfyUI checkpoints / clip / diffusion / controlnet
        "/home/*/.cache/huggingface" # redundant w/ .cache but explicit
        "**/*.safetensors"
        "**/*.ckpt"
        "**/*.gguf"
        "**/*.pt" # torch pickles (incl. quantization/lora output)
        "**/*.pth"
        "**/*.onnx"
        "**/*.h5" # keras/hdf5 weights
        "**/*.pb" # tensorflow frozen graphs
        "**/*.bin.tmp"

        # ── build/VCS scratch: regenerated by tooling ──────────────────────
        "/var/lib/docker"
        "/var/lib/containers"
        "**/node_modules"
        "**/.direnv"
        "**/result"
        "**/result-bin"
        "**/target" # rust build output
        "**/__pycache__"
        "**/.venv"
        "**/.mypy_cache"
        "**/.ruff_cache"
        "**/.pytest_cache"
      ];
      description = ''
        Glob patterns to exclude from backups. Defaults exclude everything
        re-downloadable: package/tool caches, re-fetchable ML weights
        (HuggingFace/civitai), and build scratch — so R2 only ever holds
        irreplaceable data. Override per-host if a "models" dir is actually
        curated/produced rather than re-pullable.
      '';
    };

    timerConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
      description = "systemd timer config for the periodic backup.";
    };

    pruneOpts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--keep-daily 7"
        "--keep-weekly 5"
        "--keep-monthly 12"
        "--keep-yearly 3"
      ];
      description = "Retention policy passed to `restic forget` after each backup.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Self-wire the agenix secrets by name (the .age files live in the repo).
    # A host only sets enable + paths; the module declares the secrets so there
    # is no parallel age.secrets gating. (Host imports the agenix nixos module.)
    # Only emitted when a secret name is set, so contexts without agenix (an
    # isolated VM test with passwordSecret/environmentSecret = null) never touch
    # the age option.
    age.secrets = lib.mkIf (cfg.passwordSecret != null || cfg.environmentSecret != null) (
      lib.mkMerge (
        lib.optional (cfg.passwordSecret != null) {
          ${cfg.passwordSecret}.file = machineSecrets + "/${cfg.passwordSecret}.age";
        }
        ++ lib.optional (cfg.environmentSecret != null) {
          ${cfg.environmentSecret}.file = machineSecrets + "/${cfg.environmentSecret}.age";
        }
      )
    );

    # The repo location may come from either the nix option OR the env file
    # (RESTIC_REPOSITORY). The upstream restic module asserts EXACTLY ONE of
    # repository / repositoryFile / environmentFile carries it, so when
    # .repository is empty we must pass `repository = null` and let the env
    # file provide it. This is the R2/S3 path: keeping the account-id-bearing
    # URL out of the nix store.
    assertions = [
      {
        assertion = cfg.repository != "" || cfg.environmentFile != null;
        message = ''
          hyper-modern-nixos.backup.enable is true but neither .repository nor
          .environmentFile is set. Provide the restic repo either inline via
          .repository or as RESTIC_REPOSITORY inside the agenix .environmentFile.
        '';
      }
    ];

    services.restic.backups.system = {
      # null (not "") when empty, so the upstream "exactly one" assertion passes
      # and the env file's RESTIC_REPOSITORY is the sole source of the location.
      repository = if cfg.repository == "" then null else cfg.repository;
      # Back up the operator-listed paths UNION the `authoritative` state paths
      # declared via hyper-modern-nixos.state.dirs (single source of truth — see
      # state.nix + docs/architecture/state-and-backup.md). A service that
      # classifies its state as authoritative is thereby backed up automatically,
      # with no second list to maintain here.
      paths = lib.unique (cfg.paths ++ config.hyper-modern-nixos.state.authoritativePaths);
      inherit (cfg) exclude pruneOpts;
      inherit (cfg) passwordFile;
      environmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
      inherit (cfg) timerConfig;
      # Run an integrity check after pruning so a silently-corrupt repo is caught
      # by the timer rather than discovered at restore time.
      checkOpts = [ "--read-data-subset=10%" ];
      # The repo is NOT auto-created by the backup run. Create it deliberately,
      # once, via restic-backups-init.service below (declarative + idempotent).
      initialize = false;
    };

    # ── One-time repo init (declarative, idempotent) ────────────────────────────
    # `systemctl start restic-backups-init` (or `nix run .#restic-init-<host>` if
    # wired) creates the restic repo using the EXACT same password/env/repo as
    # the backup service — no drift from a hand-typed incantation. restic init is
    # idempotent here: if the repo already exists we treat it as success, so this
    # is safe to run (or re-run) any time before trusting the timer.
    systemd.services.restic-backups-init = {
      description = "one-time `restic init` for the system backup repo";
      # Same env the backup service uses, so the repo location + creds match.
      environment.RESTIC_PASSWORD_FILE = cfg.passwordFile;
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
      }
      // lib.optionalAttrs (cfg.repository != "") {
        Environment = [ "RESTIC_REPOSITORY=${cfg.repository}" ];
      };
      script = ''
        if ${pkgs.restic}/bin/restic snapshots >/dev/null 2>&1; then
          echo "restic repo already initialized — nothing to do."
          exit 0
        fi
        echo "initializing restic repo…"
        ${pkgs.restic}/bin/restic init
      '';
    };
  };
}
