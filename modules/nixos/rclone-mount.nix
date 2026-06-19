# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                         // hyper-modern-nixos // rclone-mount
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# System-wide rclone FUSE mount of a remote (e.g. the Cloudflare R2 bucket),
# OFF BY DEFAULT. One systemd service per configured mount.
#
# The rclone config carries the R2 Access Key / Secret Access Key, so it can
# NEVER live in the nix store: the host must supply `configPath` pointing at an
# agenix-decrypted rclone.conf (root-readable). The matching user-side config
# (~/.config/rclone/rclone.conf) is handled separately by
# modules/home/cloud (the rclone-conf user secret) — this module is only the
# always-on system mount.
#
# This is the system counterpart to the per-user `straylight-r2` remote: same
# remote name, same R2 bucket, but mounted at a fixed host path by root so any
# user/service can read it. Inert until a host opts in.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.rcloneMount;
in
{
  options.hyper-modern-nixos.rcloneMount = {
    enable = lib.mkEnableOption "system-wide rclone FUSE mounts (off by default)";

    configPath = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix/rclone-conf";
      description = ''
        Path to a root-readable rclone.conf (R2 remote + creds). Must be an
        agenix runtime path, NEVER a nix store path. The host should declare a
        machine-scoped `age.secrets.rclone-conf` decrypting to this location.
      '';
    };

    mounts = lib.mkOption {
      default = { };
      description = ''
        Attrset of mounts, keyed by an arbitrary name. Each maps an rclone
        remote path (e.g. "straylight-r2:my-bucket") to a local mountpoint.
      '';
      example = lib.literalExpression ''
        {
          r2 = {
            remote = "straylight-r2:straylight-backups";
            where = "/mnt/r2";
          };
        }
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            remote = lib.mkOption {
              type = lib.types.str;
              example = "straylight-r2:straylight-backups";
              description = "rclone remote:path to mount.";
            };
            where = lib.mkOption {
              type = lib.types.str;
              example = "/mnt/r2";
              description = "Local mountpoint (created if absent).";
            };
            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                # Sane S3/R2 mount defaults: VFS cache so reads/writes don't
                # round-trip every byte, generous chunking for big objects.
                "--vfs-cache-mode=writes"
                "--dir-cache-time=12h"
                "--vfs-cache-max-age=24h"
                "--s3-no-check-bucket" # don't HEAD the bucket on every op
              ];
              description = "Extra flags appended to `rclone mount`.";
            };
            readOnly = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Mount read-only (adds --read-only).";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mounts != { };
        message = "hyper-modern-nixos.rcloneMount.enable is true but no .mounts are defined.";
      }
    ];

    # FUSE allow_other so non-root users/services can traverse the mount.
    programs.fuse.userAllowOther = true;

    environment.systemPackages = [ pkgs.rclone ];

    systemd.services = lib.mapAttrs' (
      name: m:
      lib.nameValuePair "rclone-mount-${name}" {
        description = "rclone mount ${m.remote} -> ${m.where}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "notify";
          # rclone needs the mountpoint to exist; create it first.
          ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg m.where}";
          ExecStart = lib.concatStringsSep " " (
            [
              "${pkgs.rclone}/bin/rclone mount"
              "--config=${lib.escapeShellArg (toString cfg.configPath)}"
              "--allow-other"
              (lib.escapeShellArg m.remote)
              (lib.escapeShellArg m.where)
            ]
            ++ lib.optional m.readOnly "--read-only"
            ++ m.extraArgs
          );
          ExecStop = "${pkgs.fuse}/bin/fusermount -u ${lib.escapeShellArg m.where}";
          Restart = "on-failure";
          RestartSec = 10;
        };
      }
    ) cfg.mounts;
  };
}
