#!/usr/bin/env bash
# generate the full supabase secret bundle (env file) and encrypt it with agenix.
# usage: gen-supabase-secrets [<path>]
#   default path: agenix/machines/supabase-env.age
#
# Emits ONE env file carrying every secret the supabase stack needs, mirroring
# upstream's utils/generate-keys.sh: a random JWT_SECRET, the two HS256-signed
# API-key JWTs DERIVED from it (ANON_KEY / SERVICE_ROLE_KEY), the assorted random
# keys with their exact length constraints (SECRET_KEY_BASE 64, VAULT_ENC_KEY 32,
# PG_META_CRYPTO_KEY 32+, POSTGRES_PASSWORD, DASHBOARD_*), AND the per-service DB
# connection URLs with the password embedded (GOTRUE_DB_DATABASE_URL,
# PGRST_DB_URI, storage DATABASE_URL, …) — composed HERE so the password never
# enters the nix store. The plaintext is piped straight into `agenix -e`.
#
# Re-running regenerates EVERYTHING; the JWTs are only valid against the
# JWT_SECRET emitted in the same run, so rotate as a unit.
set -euo pipefail

dest="${1:-agenix/machines/supabase-env.age}"

if [ -f "$dest" ]; then
  echo "error: '$dest' already exists — use rotate-secret to replace it" >&2
  exit 1
fi

# ── helpers ─────────────────────────────────────────────────────────────────

# url-safe base64 with no padding (JWT segments).
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

# mint an HS256 JWT: $1 = json payload, $2 = secret.
jwt_hs256() {
  local payload="$1" secret="$2" header signing sig
  header='{"alg":"HS256","typ":"JWT"}'
  signing="$(printf '%s' "$header" | b64url).$(printf '%s' "$payload" | b64url)"
  sig="$(printf '%s' "$signing" |
    openssl dgst -sha256 -hmac "$secret" -binary | b64url)"
  printf '%s.%s' "$signing" "$sig"
}

# ── key material ──────────────────────────────────────────────────────────────

# iat = now; exp ~10y out. Matches upstream's long-lived self-host API keys.
iat="$(date +%s)"
exp="$((iat + 3650 * 24 * 3600))"

jwt_secret="$(openssl rand -hex 32)"            # >= 32 chars
postgres_password="$(openssl rand -hex 24)"     # letters+digits only
secret_key_base="$(openssl rand -base64 48)"    # >= 64 chars
vault_enc_key="$(openssl rand -hex 16)"         # exactly 32 chars
pg_meta_crypto_key="$(openssl rand -base64 24)" # >= 32 chars
dashboard_password="$(openssl rand -hex 16)"

anon_key="$(jwt_hs256 \
  "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}" \
  "$jwt_secret")"
service_role_key="$(jwt_hs256 \
  "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}" \
  "$jwt_secret")"

# ── env bundle → agenix ───────────────────────────────────────────────────────
# systemd EnvironmentFile syntax: KEY=value, one per line, no surrounding quotes.
#
# This bundle carries the RAW secrets ONLY (passwords, JWT secret, derived API
# keys, the random keys). It does NOT carry composed DB URLs or per-service env:
# the module's activation oneshot (supabase-env-split) reads this bundle and
# writes the per-service env files (with the password-embedded DB URLs under each
# image's exact var name) into /run. That keeps name-collisions impossible (auth
# and storage each get their own DATABASE_URL) and the password out of the store.
mkdir -p "$(dirname "$dest")"

# Build the whole payload in a variable first, then feed agenix via a here-string.
# A `{ …; } | agenix -e` pipeline runs the producer in a subshell under
# `pipefail`, where any transient non-zero (e.g. a closed pipe) silently yields an
# EMPTY encrypted file — the bug this replaces. A here-string is unambiguous.
payload="$(
  cat <<EOF
POSTGRES_PASSWORD=$postgres_password
JWT_SECRET=$jwt_secret
ANON_KEY=$anon_key
SERVICE_ROLE_KEY=$service_role_key
SECRET_KEY_BASE=$secret_key_base
VAULT_ENC_KEY=$vault_enc_key
PG_META_CRYPTO_KEY=$pg_meta_crypto_key
DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=$dashboard_password
EOF
)"

agenix -e "$dest" <<<"$payload"

# Guard: a 0-byte ciphertext (the old failure mode) decrypts to nothing and the
# whole stack comes up credential-less. Fail loudly instead.
if [ ! -s "$dest" ]; then
  echo "error: '$dest' is empty after encryption — agenix did not receive stdin" >&2
  exit 1
fi

echo "✓ wrote $dest"
echo
echo "dashboard login: supabase / $dashboard_password"
echo "now declare it in secrets.nix:"
echo "  \"$dest\".publicKeys = mkGlobalSecret;"
