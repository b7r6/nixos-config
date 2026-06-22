# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                               // hyper-modern-nixos // dropbox
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# "Secret-gist for files": shareable URLs for private files, OFF BY DEFAULT.
#
# A public R2 bucket (`straylight-drop`) exposed via a custom domain
# (drop.s4.gl) is rclone-mounted at /mnt/r2/drop. You `drop <file>` → it lands
# under an unguessable 128-bit token dir and the matching public URL is printed.
# R2 public buckets are NOT listable, so the token is the capability: technically
# public, not crawlable. See docs/src/architecture/dropbox.md.
#
# This module:
#   - adds an rcloneMount.mounts.drop entry (the share bucket ↔ /mnt/r2/drop)
#   - installs the `drop` CLI, baked with this host's domain/mount/prefix
# It composes with rclone-mount.nix (which self-wires the rclone.conf agenix
# secret); the `straylight-drop` remote must exist in that conf.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.dropbox;
in
{
  options.hyper-modern-nixos.dropbox = {
    enable = lib.mkEnableOption "R2 dropbox (shareable URLs for private files, off by default)";

    mountEnable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Actually mount the share bucket. OFF until the `straylight-drop` remote
        exists in the rclone.conf AND the Cloudflare bucket+domain are
        provisioned — otherwise the rclone mount unit fail-loops. The `drop` CLI
        installs regardless of this (it just errors usefully until mounted), so
        you can ship the command first and flip this on post-provisioning.
      '';
    };

    remote = lib.mkOption {
      type = lib.types.str;
      default = "straylight-r2:straylight-drop";
      description = ''
        rclone remote:path backing the share. Uses the fleet `straylight-r2`
        remote (the only one in the agenix rclone.conf) pointed at the
        `straylight-drop` bucket. The bucket must have R2 public access + the
        drop.s4.gl custom domain attached (Cloudflare-side) for the printed URLs
        to actually resolve.
      '';
    };

    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/r2/drop";
      description = "Local FUSE mountpoint mapping 1:1 to the share bucket (so path == URL key).";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "drop.s4.gl";
      description = "Public custom domain fronting the bucket; `drop` builds URLs as https://<domain>/<prefix>/<token>/<file>.";
    };

    prefix = lib.mkOption {
      type = lib.types.str;
      default = "d";
      description = "Key prefix inside the bucket under which token dirs live.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Mount the public share bucket — only once provisioned (mountEnable), so we
    # don't fail-loop an rclone unit against a remote that isn't in rclone.conf
    # yet. Short dir-cache so drops/revokes show up promptly; writes cached
    # (rclone VFS) so a `cp` returns fast. Relies on rclone-mount.nix (which
    # self-wires the rclone.conf agenix secret).
    hyper-modern-nixos.rcloneMount.enable = lib.mkIf cfg.mountEnable (lib.mkDefault true);
    hyper-modern-nixos.rcloneMount.mounts = lib.mkIf cfg.mountEnable {
      drop = {
        remote = cfg.remote;
        where = cfg.mountPoint;
        readOnly = false;
        extraArgs = [
          "--vfs-cache-mode=writes"
          "--dir-cache-time=5s"
          "--s3-no-check-bucket"
        ];
      };
    };

    # Ensure the mountpoint dir exists even before mounting, so `drop --ls`
    # gives a clean "(no drops)" instead of a confusing error.
    systemd.tmpfiles.rules = [ "d ${cfg.mountPoint} 0755 root root - -" ];

    # The `drop` CLI, baked with this host's domain/mount/prefix.
    environment.systemPackages = [
      (pkgs.callPackage ../../packages/drop {
        dropMount = cfg.mountPoint;
        dropDomain = cfg.domain;
        dropPrefix = cfg.prefix;
      })
    ];
  };
}
