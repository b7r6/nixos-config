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
        "/home/*/.cache"
        "/home/*/.local/share/Trash"
        "/home/*/.local/state/nix"
        "/var/lib/docker"
        "/var/lib/containers"
        "**/node_modules"
        "**/.direnv"
        "**/result"
        "**/target"
      ];
      description = "Glob patterns to exclude from backups.";
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
    assertions = [
      {
        assertion = cfg.repository != "";
        message = "hyper-modern-nixos.backup.enable is true but .repository is empty. Set the restic repository before enabling.";
      }
    ];

    services.restic.backups.system = {
      inherit (cfg)
        repository
        paths
        exclude
        pruneOpts
        ;
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
