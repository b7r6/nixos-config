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

  # Tailscale auth key for the live tailnet (the MagicDNS suffix is NOT pinned
  # here — it lives once in hyper-modern-nixos.network.tailnet.domain). Consumed by
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
  "agenix/machines/restic-r2-env.guccimane.age".publicKeys = mkGlobalSecret;
  "agenix/machines/restic-r2-env.shimmer.age".publicKeys = mkGlobalSecret;
  "agenix/machines/restic-r2-env.weyl.age".publicKeys = mkGlobalSecret;
  "agenix/machines/restic-r2-env.shannon.age".publicKeys = mkGlobalSecret;

  # nativelink R2 backend creds (env file, shellexpand'd in the JSON5 config):
  #   R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
  "agenix/machines/nativelink-r2-env.age".publicKeys = mkGlobalSecret;

  # zot OCI registry R2 creds (AWS SDK env vars, consumed by the s3 storage
  # driver via systemd EnvironmentFile):
  #   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
  # Dedicated R2 bucket straylight-oci (blobs are reconstructible — not restic'd).
  "agenix/machines/zot-r2-env.age".publicKeys = mkGlobalSecret;

  # Njalla API token for ACME DNS-01 against s4.gl (internal nginx vhost certs).
  # env file: NJALLA_TOKEN=<token>. Consumed by lego via security.acme
  # credentialsFile; scoped to DNS-record management on s4.gl.
  "agenix/machines/njalla-acme-token.age".publicKeys = mkGlobalSecret;

  # pgBackRest PITR repo creds for the dedicated R2 bucket. env file exporting
  # the S3 secrets as PGBACKREST_* vars so they never enter the nix store:
  #   PGBACKREST_REPO1_S3_KEY=<r2 access key id>
  #   PGBACKREST_REPO1_S3_KEY_SECRET=<r2 secret access key>
  # R2 token scoped Object R&W to JUST the straylight-pg-pitr bucket. Global so
  # any operator box can drive a restore.
  "agenix/machines/pgbackrest-r2-env.age".publicKeys = mkGlobalSecret;

  # atticd RS256 JWT signing secret (single-line env var — systemd
  # EnvironmentFile can't parse a multi-line PEM). MUST be identical on every
  # atticd instance so tokens verify fleet-wide:
  #   ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<base64 -w0 of an RSA PKCS1 PEM>
  #   (also carries AWS_*/R2 creds for the shared S3/R2 chunk store)
  # Generate:  openssl genrsa -traditional 4096 | base64 -w0
  "agenix/machines/atticd-rs256.age".publicKeys = mkGlobalSecret;

  # forgejo database password for the PG17 supabase cluster:
  #   PGPASSWORD=<random base64 string>
  # Generate:  openssl rand -base64 32
  "agenix/machines/forgejo-db.age".publicKeys = mkGlobalSecret;

  # kanidm admin password (used for provisioning — raw password, no KEY=VAL)
  # Generate:  openssl rand -base64 24
  "agenix/machines/kanidm-admin-password.age".publicKeys = mkGlobalSecret;

  # kanidm oauth2 basic secret for the forgejo client (raw secret, no KEY=VAL)
  # Generate:  openssl rand -base64 32
  "agenix/machines/kanidm-forgejo-secret.age".publicKeys = mkGlobalSecret;
  "agenix/machines/kanidm-grafana-secret.age".publicKeys = mkGlobalSecret;

  # oauth2-proxy per-host secrets (client secret + cookie encryption)
  "agenix/machines/oauth2-proxy-ultraviolence-secret.age".publicKeys = mkGlobalSecret;
  "agenix/machines/oauth2-proxy-ultraviolence-cookie.age".publicKeys = mkGlobalSecret;
  "agenix/machines/oauth2-proxy-guccimane-secret.age".publicKeys = mkGlobalSecret;
  "agenix/machines/oauth2-proxy-guccimane-cookie.age".publicKeys = mkGlobalSecret;

  # litestream R2 credentials for kanidm SQLite replication:
  #   AWS_ACCESS_KEY_ID=<r2 access key>
  #   AWS_SECRET_ACCESS_KEY=<r2 secret key>
  "agenix/machines/litestream-r2-env.age".publicKeys = mkGlobalSecret;

  # clickhouse S3 disk R2 credentials:
  #   AWS_ACCESS_KEY_ID=<r2 access key>
  #   AWS_SECRET_ACCESS_KEY=<r2 secret key>
  "agenix/machines/clickhouse-r2-env.age".publicKeys = mkGlobalSecret;

  # grafana admin password (raw password, no KEY=VAL)
  # Generate:  openssl rand -base64 24
  "agenix/machines/grafana-admin-password.age".publicKeys = mkGlobalSecret;

  # attic PUSH token (raw JWT, push+pull on the `hypermodern` cache). Used by
  # each host's watch-store to self-populate the shared cache:
  #   atticd-atticadm make-token --sub <host>-push --validity 10y \
  #     --pull hypermodern --push hypermodern
  "agenix/machines/attic-push-token.age".publicKeys = mkGlobalSecret;

  # attic CACHE SIGNING KEYPAIR (the NixKeypair string for the `hypermodern`
  # cache). attic stores this ONLY in the postgres `cache` table and has no
  # import CLI — so a postgres wipe regenerates it and every client's trusted
  # public key breaks. We persist it here and restore it into the cache table on
  # activation (monolithic-shared node) so the signing identity is STABLE and
  # recoverable regardless of postgres state. Public key:
  #   hypermodern:x+kBunu5nD1KOhzCIawyZeq8w0LV0GC6A7suIRoHTm8=
  "agenix/machines/attic-cache-keypair.age".publicKeys = mkGlobalSecret;

  # Supabase stack secrets — ONE env file consumed by every service unit via
  # systemd EnvironmentFile (modules/nixos/supabase). Generated as a unit by
  # `nix run .#gen-supabase-secrets` (mirrors upstream utils/generate-keys.sh):
  #   JWT_SECRET                      (>= 32 chars; HS256 signer)
  #   ANON_KEY / SERVICE_ROLE_KEY     (HS256 JWTs DERIVED from JWT_SECRET)
  #   POSTGRES_PASSWORD               (the supabase cluster's postgres password)
  #   SECRET_KEY_BASE (64) / VAULT_ENC_KEY (32) / PG_META_CRYPTO_KEY (32+)
  #   DASHBOARD_USERNAME / DASHBOARD_PASSWORD   (Studio basic-auth)
  # The ANON/SERVICE JWTs are only valid against the JWT_SECRET in the SAME file,
  # so rotate the bundle as a unit. Never enters the nix store.
  "agenix/machines/supabase-env.age".publicKeys = mkGlobalSecret;

  # nix daemon access-tokens — a nix.conf FRAGMENT `!include`d into the daemon
  # config (modules/nixos/nix.nix), so private flake inputs (github:sensenet-ai/*)
  # resolve fleet-wide with NO hand-exported NIX_CONFIG. Contents are literally a
  # nix.conf line:
  #   access-tokens = github.com=ghp_xxxxxxxxxxxxxxxxxxxx
  # Use a fine-grained / classic PAT with read scope on the private repos (NOT the
  # short-lived `gh auth token`, which expires) so it survives reboots. Never
  # enters the nix store.
  "agenix/machines/nix-access-tokens.age".publicKeys = mkGlobalSecret;

  # SearXNG signing key env file: SEARXNG_SECRET=<openssl rand -hex 32>.
  "agenix/machines/searxng-env.age".publicKeys = mkGlobalSecret;

  # transmission RPC secret (JSON): {"rpc-password":"…"}. transmission salts it
  # on first start.
  "agenix/machines/transmission-rpc.age".publicKeys = mkGlobalSecret;

  # ── User Secrets (agenix-deployed via home-manager) ──────────────────────────
  "agenix/users/b7r6/netrc.age".publicKeys = mkGlobalSecret;
  "agenix/users/b7r6/atuin-key.age".publicKeys = mkGlobalSecret;
  "agenix/users/b7r6/hf-token.age".publicKeys = mkGlobalSecret;
  "agenix/users/b7r6/njalla-api-key.age".publicKeys = mkGlobalSecret;
  "agenix/users/b7r6/cloudflare-r2-env.age".publicKeys = mkGlobalSecret;
  "agenix/users/b7r6/forgejo-token.age".publicKeys = mkGlobalSecret;

  # Full rclone.conf (R2 remote `straylight-r2` + creds). Decrypted by the
  # home-manager agenix module to ~/.config/rclone/rclone.conf (0600), and also
  # at the NixOS level for the system rclone mount. Same R2 token as restic.
  "agenix/users/b7r6/rclone-conf.age".publicKeys = mkGlobalSecret;
}
