# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hyper-modern-nixos // secrets/keys
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Single source of truth for age/agenix HOST recipient public keys. Consumed by:
#   - secrets/secrets.nix  (recipient sets for every .age secret)
#   - any module that needs a peer's host key (knownHosts, build machines, …)
#
# This file is DATA ONLY: one attrset, `hosts`, mapping a host to its
# ssh-ed25519 host key(s). agenix accepts SSH ed25519 keys directly (no
# ssh-to-age conversion needed).
#
# n.b. USER recipients are NOT here anymore — they derive from the fleet user
# registry (modules/flake/registry/data/users.dhall): the fleet_admins group's
# sshKeys are rendered to secrets/admin-recipients.json (regenerate with
# `nix run .#render-admin-recipients`; a flake check guards staleness). This is
# the "one source of truth for identity" carried through to secret access.
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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOVmQ8pwaRwgrDpZMriiMIuFVamndu1OxhbWykeqqTpy root@gossamer"
    ];
  };
}
