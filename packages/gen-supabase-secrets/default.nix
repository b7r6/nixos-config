# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                   // hyper-modern-nixos // gen-supabase-secrets
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Compiled Supabase secret-bundle generator: JWT via crypton (not openssl|tr),
# secure random via entropy, agenix invocation via Shelly (no pipefail trap).
{ haskell }:
let
  hp = haskell.packages.ghc912;
in
hp.callCabal2nix "gen-supabase-secrets" ./. { }
