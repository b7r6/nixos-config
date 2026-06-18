# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // backup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# restic-based backups, OFF BY DEFAULT.
#
# Philosophy (per the runbook in BACKUP.md): do the FIRST backup BY HAND so you
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
# Manual first run (see BACKUP.md for the full runbook), e.g. for a local repo:
#   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
#     restic -r /path/to/repo init
#   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
#     restic -r /path/to/repo backup /home /etc /var/lib
#   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
#     restic -r /path/to/repo snapshots          # verify
# then set hyper-modern-nixos.backup.enable = true and rebuild.

{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.backup;
in
{
  options.hyper-modern-nixos.backup = {
    enable = lib.mkEnableOption "restic backups (off by default; do the first run by hand)";

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
      default = "/run/agenix/restic-password";
      description = ''
        Path to the file containing the restic repository password. Defaults to
        the conventional agenix runtime path; a host that enables backups should
        declare `age.secrets.restic-password` (file = restic-password.age) and
        import the agenix nixos module. NEVER put this in the nix store.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
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
      inherit (cfg) paths exclude pruneOpts;
      inherit (cfg) passwordFile;
      environmentFile = lib.mkIf (cfg.environmentFile != null) cfg.environmentFile;
      inherit (cfg) timerConfig;
      # Run an integrity check after pruning so a silently-corrupt repo is caught
      # by the timer rather than discovered at restore time.
      checkOpts = [ "--read-data-subset=10%" ];
      initialize = false; # the repo MUST be created by hand first (see runbook).
    };
  };
}
