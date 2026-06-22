# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                         // hyper-modern-nixos // rclone-mount
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# System-wide rclone FUSE mounts of a remote (the Cloudflare R2 bucket).
#
# Two layers:
#   - `r2` : the fleet convenience. When enabled (DEFAULT ON fleet-wide), every
#     host gets TWO mounts under /mnt/r2:
#       /mnt/r2/common      → straylight-r2:host-mount/common   (SHARED by all)
#       /mnt/r2/<hostname>  → straylight-r2:host-mount/<host>   (this host only)
#     The per-host subtree name comes from config.networking.hostName, so there
#     is nothing per-host to configure — importing the module is enough.
#   - `mounts` : the low-level escape hatch. An arbitrary attrset of
#     remote→mountpoint mappings for anything outside the r2 convention.
#
# The rclone config carries the R2 Access Key / Secret Access Key, so it can
# NEVER live in the nix store: the module SELF-WIRES an agenix secret (the same
# rclone.conf the per-user `straylight-r2` remote uses, encrypted to all host
# keys too) and decrypts it to a root-readable runtime path. A host only flips
# enable (or inherits the fleet default); no per-host age.secrets needed.
{
  config,
  lib,
  pkgs,
  flake ? null,
  ...
}:
let
  cfg = config.hyper-modern-nixos.rcloneMount;

  # Sane S3/R2 mount defaults: VFS cache so reads/writes don't round-trip every
  # byte, generous chunking for big objects, and no per-op bucket HEAD.
  defaultArgs = [
    "--vfs-cache-mode=writes"
    "--dir-cache-time=12h"
    "--vfs-cache-max-age=24h"
    "--s3-no-check-bucket"
  ];

  # The fleet R2 convention mounts, derived purely from the hostname. Only
  # materialised when cfg.r2.enable is true.
  host = config.networking.hostName;
  r2Mounts = lib.optionalAttrs cfg.r2.enable {
    common = {
      remote = "${cfg.r2.remote}:${cfg.r2.bucket}/common";
      where = "${cfg.r2.base}/common";
      extraArgs = defaultArgs;
      readOnly = false;
    };
    host = {
      remote = "${cfg.r2.remote}:${cfg.r2.bucket}/${host}";
      where = "${cfg.r2.base}/${host}";
      extraArgs = defaultArgs;
      readOnly = false;
    };
  };

  # The r2 convenience + any explicit low-level mounts, merged. Explicit `mounts`
  # win on key collision (mergeAttrs is right-biased).
  allMounts = r2Mounts // cfg.mounts;

  anyEnabled = cfg.r2.enable || cfg.mounts != { };
in
{
  options.hyper-modern-nixos.rcloneMount = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Master switch for the system rclone mount service. When off, NO mounts
        are created regardless of the r2/mounts settings below. Fleet default is
        set in modules/nixos/default.nix.
      '';
    };

    configPath = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix/rclone-conf";
      description = ''
        Path to a root-readable rclone.conf (R2 remote + creds). An agenix
        runtime path, NEVER a nix store path. The module self-wires the matching
        agenix secret (see `secret`) so this resolves on every host.
      '';
    };

    secret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "users/b7r6/rclone-conf";
      description = ''
        agenix secret path (under secrets/agenix/, without the .age suffix) for
        the rclone.conf. The module wires age.secrets.rclone-conf.file from the
        repo so no host needs to declare it. Set null to wire configPath
        yourself (e.g. an isolated test).
      '';
    };

    # ── R2 fleet convenience ────────────────────────────────────────────────────
    r2 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Mount the standard fleet R2 layout: a SHARED /mnt/r2/common and a
          per-host /mnt/r2/<hostname>, both off the `straylight-r2` remote's
          `host-mount` bucket. Default on; gated by the master `enable`.
        '';
      };

      remote = lib.mkOption {
        type = lib.types.str;
        default = "straylight-r2";
        description = "rclone remote name (from the decrypted rclone.conf).";
      };

      bucket = lib.mkOption {
        type = lib.types.str;
        default = "host-mount";
        description = "R2 bucket holding the common + per-host subtrees.";
      };

      base = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/r2";
        description = "Local base dir under which common/ and <hostname>/ are mounted.";
      };
    };

    mounts = lib.mkOption {
      default = { };
      description = ''
        Low-level escape hatch: an attrset of extra mounts keyed by an arbitrary
        name, each mapping an rclone remote path to a local mountpoint. Merged
        with (and overriding) the r2 convenience mounts.
      '';
      example = lib.literalExpression ''
        {
          archive = {
            remote = "straylight-r2:cold-archive";
            where = "/mnt/r2-archive";
            readOnly = true;
          };
        }
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            remote = lib.mkOption {
              type = lib.types.str;
              example = "straylight-r2:host-mount/common";
              description = "rclone remote:path to mount.";
            };
            where = lib.mkOption {
              type = lib.types.str;
              example = "/mnt/r2/common";
              description = "Local mountpoint (created if absent).";
            };
            extraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = defaultArgs;
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

  config = lib.mkIf (cfg.enable && anyEnabled) {
    # Self-wire the rclone.conf agenix secret (the .age lives in the repo), so a
    # host inherits the fleet default with nothing to declare. Only when a secret
    # name is set (test contexts pass null and wire configPath themselves).
    age.secrets = lib.mkIf (cfg.secret != null) {
      rclone-conf.file = flake.self + "/secrets/agenix/${cfg.secret}.age";
    };

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
    ) allMounts;
  };
}
