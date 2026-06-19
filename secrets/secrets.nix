# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hyper-modern-nixos // secrets/secrets.nix
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Agenix secret definitions - specifies which public keys can decrypt each secret.
#
# Secrets are organized as:
#   - agenix/machines/<secret>.age  → Machine-level secrets (host keys)
#   - agenix/users/<user>/<secret>.age → User secrets deployed via home-manager
#
# Interactive secrets live in passage-store/ and are NOT managed by agenix.
#
let
  keys = import ./keys.nix;

  # Helper: get all keys for a user
  userKeys = user: keys.users.${user} or [ ];

  # Helper: get all keys for a host (returns empty list if not yet configured)
  hostKeys = host: keys.hosts.${host} or [ ];

  # Helper: combine user keys with specific host keys

  # All hosts that have keys configured
  allConfiguredHosts = builtins.filter (h: (hostKeys h) != [ ]) (builtins.attrNames keys.hosts);

  # b7r6's keys + all configured hosts (for secrets that should be accessible everywhere)
  b7r6Everywhere = (userKeys "b7r6") ++ (builtins.concatLists (map hostKeys allConfiguredHosts));
in
{
  # ── Machine Secrets ──────────────────────────────────────────────────────────
  # Deployed to /run/agenix/ on the target machine
  # Encrypted to: user keys (for editing) + target host key (for deployment)

  # Tailscale auth keys - one per tailnet, deployed to machines that need them
  "agenix/machines/tailscale-auth-key.parabolic-surf.age".publicKeys = b7r6Everywhere;
  "agenix/machines/tailscale-auth-key.straylight-evaluation.age".publicKeys = b7r6Everywhere;
  "agenix/machines/tailscale-auth-key.v4.surf.age".publicKeys = b7r6Everywhere;

  # restic repository password (consumed by modules/nixos/common/backup.nix when
  # hyper-modern-nixos.backup.enable is set on a host). High-entropy passphrase,
  # e.g. `openssl rand -base64 48`. LOSING THIS = UNRECOVERABLE BACKUPS; keep an
  # independent copy somewhere out-of-band.
  "agenix/machines/restic-password.age".publicKeys = b7r6Everywhere;

  # restic backend env file for the Cloudflare R2 (S3-compatible) repository.
  # Consumed via services.restic.backups.system.environmentFile. Contents:
  #   RESTIC_REPOSITORY=s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/<BUCKET>
  #   AWS_ACCESS_KEY_ID=<R2 token Access Key ID>
  #   AWS_SECRET_ACCESS_KEY=<R2 token Secret Access Key>
  #   AWS_DEFAULT_REGION=auto
  # The R2 token must be Object Read & Write scoped to JUST that one bucket.
  "agenix/machines/restic-r2-env.age".publicKeys = b7r6Everywhere;

  # nativelink R2 backend creds (env file). Consumed via the nativelink
  # service's EnvironmentFile; the JSON config references them as
  # ${R2_ACCESS_KEY_ID} / ${R2_SECRET_ACCESS_KEY} (shellexpand), so no creds
  # touch the store. Contents:
  #   R2_ACCESS_KEY_ID=<R2 token Access Key ID>
  #   R2_SECRET_ACCESS_KEY=<R2 token Secret Access Key>
  "agenix/machines/nativelink-r2-env.age".publicKeys = b7r6Everywhere;

  # atticd RS256 JWT signing secret env file (consumed by attic.nix when
  # hyper-modern-nixos.attic.enable is set). Must be a SINGLE-LINE env var, since
  # systemd EnvironmentFile can't parse a multi-line PEM:
  #   ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<base64 -w0 of an RSA PKCS1 PEM>
  # Generate:  openssl genrsa -traditional 4096 | base64 -w0
  "agenix/machines/atticd-rs256.age".publicKeys = b7r6Everywhere;

  # attic PUSH token (raw JWT, push+pull scoped to the `hypermodern` cache).
  # Referenced by the post-build-hook's attic client config as `token-file` so
  # every successful build self-populates the cache. Generate from the server:
  #   atticd-atticadm make-token --sub <host>-push --validity 10y \
  #     --pull hypermodern --push hypermodern
  "agenix/machines/attic-push-token.age".publicKeys = b7r6Everywhere;

  # ── User Secrets (agenix-deployed) ───────────────────────────────────────────
  # Deployed to user's home via home-manager agenix module
  # Encrypted to: user keys + hosts where that user exists

  # b7r6's secrets - accessible from any machine b7r6 logs into
  "agenix/users/b7r6/netrc.age".publicKeys = b7r6Everywhere;
  "agenix/users/b7r6/atuin-key.age".publicKeys = b7r6Everywhere;
  "agenix/users/b7r6/hf-token.age".publicKeys = b7r6Everywhere;

  # Full rclone.conf (R2 remote `straylight-r2` + its Access Key / Secret Access
  # Key). Decrypted by the home-manager agenix module straight to
  # ~/.config/rclone/rclone.conf (mode 600) when hyper-modern-nixos.cloud.rclone
  # is enabled. Same R2 token as the restic backups; reuse is fine.
  "agenix/users/b7r6/rclone-conf.age".publicKeys = b7r6Everywhere;
}
