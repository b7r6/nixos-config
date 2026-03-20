# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                              // hyper-modern-nixos // secrets/keys
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Public keys for age encryption. Used by both agenix (NixOS secrets) and
# passage (interactive password store).
#
# To add a host key:
#   ssh-keyscan -t ed25519 <hostname> 2>/dev/null | cut -d' ' -f2-
#   # or from the host: cat /etc/ssh/ssh_host_ed25519_key.pub
#
# To convert SSH key to age format (for reference):
#   ssh-to-age < ~/.ssh/id_ed25519.pub
#
{
  # ── User Keys ────────────────────────────────────────────────────────────────
  # Personal SSH keys that can decrypt user-scoped secrets

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
  # Machine SSH host keys - secrets encrypted to these are deployed via agenix
  # Run: ssh-keyscan -t ed25519 <host> 2>/dev/null | cut -d' ' -f2-

  hosts = {
    # ── aarch64-linux ──
    shimmer = [
      # TODO: Add after first boot
      # "ssh-ed25519 AAAAC3NzaC1..."
    ];

    # ── x86_64-linux ──
    weyl = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDlQI/GVzQ5wtvZITk9fkPIv/2ssXsnzpG+ZXZJxJ+HZ root@weyl"
    ];

    noether = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILo8tDMB+M0T/Bj32ocGAU2yBCxYoiWzotQ1PE4S9I0h root@nixos"
    ];

    shannon = [
      # TODO: ssh-keyscan -t ed25519 shannon
    ];

    watchtower = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIaKgH3tdEU5G+9bTQ9K9ldT55t8mBNRzTX8PfoVmjGb watchtower"
    ];

    beratna = [
      # TODO: ssh-keyscan -t ed25519 beratna
    ];

    flatline = [
      # TODO: ssh-keyscan -t ed25519 flatline
    ];

    galois = [
      # TODO: ssh-keyscan -t ed25519 galois
    ];

    guccimane = [
      # TODO: ssh-keyscan -t ed25519 guccimane
    ];

    railgun = [
      # TODO: ssh-keyscan -t ed25519 railgun
    ];

    ultralight = [
      # TODO: ssh-keyscan -t ed25519 ultralight
    ];

    ultraviolence = [
      # TODO: ssh-keyscan -t ed25519 ultraviolence
    ];
  };
}
