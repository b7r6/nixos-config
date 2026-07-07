# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hyper-modern-nixos // secrets/keys
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Single source of truth for age/agenix recipient public keys. Consumed by:
#   - secrets/secrets.nix  (recipient sets for every .age secret)
#   - any module that needs a peer's host key (knownHosts, build machines, …)
#
# This file is DATA ONLY: two attrsets, `users` and `hosts`, mapping a name to
# a list of ssh-ed25519 public keys. agenix accepts SSH ed25519 keys directly
# (no ssh-to-age conversion needed).
#
# ── Adding / rotating a host key ───────────────────────────────────────────
#   ssh-keyscan -t ed25519 <host> 2>/dev/null | grep -v '^#' | awk '{print $2,$3}'
#   # or, authoritative, from the host itself:
#   ssh <host> cat /etc/ssh/ssh_host_ed25519_key.pub
#
# A host can only DECRYPT a secret once its key is listed here AND the secret
# has been (re)keyed to include it (`agenix -r` / the `rekey` devshell cmd).
#
# ── The live fleet ─────────────────────────────────────────────────────────
#   ultraviolence  x86_64  NixOS    primary workstation / infra host
#   watchtower     x86_64  NixOS    services host (postgres, attic state, GC)
#   weyl           x86_64  NixOS
#   guccimane      x86_64  NixOS
#   shimmer        aarch64 NixOS    DGX Spark (GB10)
#   shannon        x86_64  NixOS    laptop (frequently powered down, still fleet)
#   gossamer       aarch64 NixOS    DGX Spark (GB10) — secondary compute node
#
# Decommissioned & removed from the fleet (do not re-add without a real host):
#   beratna, flatline, galois, noether, railgun, ultralight
#
{
  # ── User Keys ──────────────────────────────────────────────────────────────
  # Personal SSH keys that can decrypt every secret (for editing/rekeying).
  users = {
    b7r6 = [
      # Primary key (id_ed25519)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINbn+XF6n9v9VKLFGLBVz+G1LyL6GlcgZbIwhP89PPsp"
      # Named key (id_ed25519_b7r6)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1ptqyz5C3YCcMgh3LUbXtjeS1rIZ5/6RHnH7D93Nqf"
      # Yubikey-resident key (if applicable)
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILBEaqZY7H09brD/syW20HVDpYmKf44TOZ/Whzemwc/+"
    ];
  };

  # ── Host Keys ────────────────────────────────────────────────────────────────
  # Machine SSH host keys (ed25519). Secrets encrypted to these are decryptable
  # by the corresponding host's /etc/ssh/ssh_host_ed25519_key at activation.
  # All keys below were read directly from the live hosts (authoritative).
  hosts = {
    # ── x86_64-linux ──
    ultraviolence = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIByLBDrGF8XgGFi9TdWS65haJBZYGEbAHLSu+q3LaGP5"
    ];

    watchtower = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMibWXJ2mjqlJi0j8hlNP7OgiUZ7jG8dB1vZ75fNH0Cy" ];

    weyl = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIITOOlNpHBYnG7EmU3lXqrSzf4AqMHxpViF8HS90QTiK" ];

    guccimane = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIADHEWWzCpRcLIjk1CNKnl86dtAap7BHfsaijUqe3cV7" ];

    shannon = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMbJUUAOq1ZviJYmM9G2i9Mnmcps7UTNKhPm9ILCMeNJ" ];

    # ── aarch64-linux ──
    shimmer = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAFyVtrt3AmJrLqcdAnZn5hXrvMenOUKGAS182qBnuYN" ];

    # ── non-NixOS → NixOS converted ──
    # gossamer freshly installed via nixos-anywhere 2026-07-06
    gossamer = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINIiiPOjVfmCk3AzW00dOmZNNYa46nkoy6sCTUi2xM3g root@gossamer"
    ];
  };
}
