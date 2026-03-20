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
  userAndHosts = user: hosts: (userKeys user) ++ (builtins.concatLists (map hostKeys hosts));

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

  # ── User Secrets (agenix-deployed) ───────────────────────────────────────────
  # Deployed to user's home via home-manager agenix module
  # Encrypted to: user keys + hosts where that user exists

  # b7r6's secrets - accessible from any machine b7r6 logs into
  "agenix/users/b7r6/netrc.age".publicKeys = b7r6Everywhere;
  "agenix/users/b7r6/atuin-key.age".publicKeys = b7r6Everywhere;
  "agenix/users/b7r6/hf-token.age".publicKeys = b7r6Everywhere;
  "agenix/users/b7r6/cachix-token.age".publicKeys = b7r6Everywhere;
}
