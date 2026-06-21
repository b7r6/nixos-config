# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hyper-modern-nixos // secrets/secrets.nix
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# agenix secret definitions: which public keys may decrypt each .age secret.
# Recipient sets are derived from secrets/keys.nix (the single source of truth)
# via the mkSecret / mkGlobalSecret helpers below, so adding a host to keys.nix
# and re-keying is all it takes to extend access — no per-secret edits.
#
# Layout:
#   agenix/machines/<secret>.age        → machine secrets → /run/agenix/ (root)
#   agenix/users/<user>/<secret>.age    → user secrets via home-manager agenix
#   passage-store/                      → interactive secrets, NOT agenix-managed
#
# ── Recipient model ──────────────────────────────────────────────────────────
# Every secret is always encrypted to ALL user keys (so any operator can edit /
# rekey). `mkSecret [hosts…]` adds the named hosts; `mkGlobalSecret` adds every
# configured host. Today everything is global (single operator, mutually-trusted
# fleet); the mkSecret helper exists so future least-privilege scoping is a
# one-line change per secret rather than a structural refactor.
#
let
  keys = import ./keys.nix;

  inherit (builtins)
    attrNames
    attrValues
    concatLists
    concatMap
    filter
    ;

  # All user public keys, flattened.
  allUserKeys = concatLists (attrValues keys.users);

  # Hosts that actually have a key listed (skip TODO stubs like a powered-down
  # laptop), so we never try to encrypt to an empty recipient.
  configuredHosts = filter (h: (keys.hosts.${h} or [ ]) != [ ]) (attrNames keys.hosts);

  # mkSecret: recipients = all users + the named hosts' keys.
  # Unknown / unconfigured host names contribute nothing (or [ ]).
  mkSecret = hostList: allUserKeys ++ (concatMap (h: keys.hosts.${h} or [ ]) hostList);

  # mkGlobalSecret: recipients = all users + every configured host.
  mkGlobalSecret = mkSecret configuredHosts;
in
{
  # ── Machine Secrets ──────────────────────────────────────────────────────────
  # Decrypted to /run/agenix/ on the target host (root, 0400).

  # Tailscale auth keys. NOTE: the three below are STALE — they were minted for
  # Tailscale auth key for the live tailnet (osiris-walleye.ts.net). Consumed by
  # hyper-modern-nixos.network.tailscale.authKeyFile for DECLARATIVE enrollment:
  # a host with this wired joins the tailnet non-interactively, so a rebuild /
  # reinstall can't strand a remote box. Use a REUSABLE, PRE-AUTHORIZED key
  # (ideally tagged + ephemeral=false) from the Tailscale admin console. The 3
  # prior keys (parabolic-surf / straylight-evaluation / v4.surf) were for
  # retired tailnets and have been removed.
  "agenix/machines/tailscale-auth-key.age".publicKeys = mkGlobalSecret;

  # restic repository password (modules/nixos/common/backup.nix). High-entropy
  # passphrase (`openssl rand -base64 48`). LOSING THIS = UNRECOVERABLE BACKUPS;
  # keep an independent out-of-band copy.
  "agenix/machines/restic-password.age".publicKeys = mkGlobalSecret;

  # restic R2 backend env file, ONE PER HOST (services.restic…environmentFile):
  #   RESTIC_REPOSITORY=s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/<BUCKET>/<host>
  #   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_DEFAULT_REGION=auto
  # Per-host so each machine gets an isolated repo (own locks, own retention)
  # under a per-host prefix in the shared bucket. R2 token scoped Object R&W to
  # JUST the backups bucket. Kept mkGlobalSecret so any operator box can restore
  # any host's repo.
  "agenix/machines/restic-r2-env.ultraviolence.age".publicKeys = mkGlobalSecret;
  "agenix/machines/restic-r2-env.watchtower.age".publicKeys = mkGlobalSecret;

  # nativelink R2 backend creds (env file, shellexpand'd in the JSON5 config):
  #   R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
  "agenix/machines/nativelink-r2-env.age".publicKeys = mkGlobalSecret;

  # atticd RS256 JWT signing secret (single-line env var — systemd
  # EnvironmentFile can't parse a multi-line PEM). MUST be identical on every
  # atticd instance so tokens verify fleet-wide:
  #   ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<base64 -w0 of an RSA PKCS1 PEM>
  #   (also carries AWS_*/R2 creds for the shared S3/R2 chunk store)
  # Generate:  openssl genrsa -traditional 4096 | base64 -w0
  "agenix/machines/atticd-rs256.age".publicKeys = mkGlobalSecret;

  # attic PUSH token (raw JWT, push+pull on the `hypermodern` cache). Used by
  # each host's watch-store to self-populate the shared cache:
  #   atticd-atticadm make-token --sub <host>-push --validity 10y \
  #     --pull hypermodern --push hypermodern
  "agenix/machines/attic-push-token.age".publicKeys = mkGlobalSecret;

  # ── User Secrets (agenix-deployed via home-manager) ──────────────────────────
  "agenix/users/b7r6/netrc.age".publicKeys = mkGlobalSecret;
  "agenix/users/b7r6/atuin-key.age".publicKeys = mkGlobalSecret;
  "agenix/users/b7r6/hf-token.age".publicKeys = mkGlobalSecret;

  # Full rclone.conf (R2 remote `straylight-r2` + creds). Decrypted by the
  # home-manager agenix module to ~/.config/rclone/rclone.conf (0600), and also
  # at the NixOS level for the system rclone mount. Same R2 token as restic.
  "agenix/users/b7r6/rclone-conf.age".publicKeys = mkGlobalSecret;
}
