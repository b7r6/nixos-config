# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                       // hyper-modern-nixos // nixos modules
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The single NixOS module every host imports. It pulls in:
#   - always-on essentials (base, nix, packages, greetd, users, network…)
#   - every gated service/hardware module (attic, backup, nativelink, postgres,
#     docker, libvirt, nvidia, radeon, …) which stay INERT until a host sets the
#     corresponding hyper-modern-nixos.<x>.enable = true
#   - the dgx-spark and wayland subtrees
#
# Flat layout: each module is a sibling file here (no common/ or services/
# nesting). Gated modules cost nothing when off, so importing them all keeps
# host configs to "import this + set options" with zero per-host import lists.
{ ... }: {
  imports = [
    # ── Core system (always-on) ──
    ./base.nix
    ./nix.nix
    ./packages.nix
    ./greetd.nix
    ./myusers.nix
    ./secrets.nix

    # ── Hardware (gated) ──
    ./bluetooth.nix
    ./nvidia.nix
    ./radeon.nix
    ./usb.nix

    # ── Networking ──
    ./network.nix
    ./network-manager.nix

    # ── Virtualization & containers (gated) ──
    ./docker.nix
    ./libvirt.nix

    # ── Services (gated) ──
    ./postgres.nix
    ./backup.nix
    ./attic.nix
    ./nativelink.nix
    ./rclone-mount.nix

    # ── Development ──
    ./android.nix
    ./appimage.nix
    ./nix-ld.nix

    # ── Special ──
    ./impermanence.nix
    ./impurity.nix
    ./xremap.nix

    # ── Subtrees ──
    ./dgx-spark
    ./wayland
  ];

  # ── Fleet-wide network defaults ─────────────────────────────────────────────
  hyper-modern-nixos.network = {
    enable = true;
    tailnet.domain = "osiris-walleye.ts.net";
    firewall.enable = false;
    useBackupResolver = true;
  };

  # ── Fleet-wide user model ───────────────────────────────────────────────────
  # Groups + SSH keys declared ONCE here apply to every managed user on every
  # host (see myusers.nix). Per-host/per-user extras go in
  # hyper-modern-nixos.users.users.<name>.{extraGroups,authorizedKeys}.
  hyper-modern-nixos.users = {
    defaultAuthorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINbn+XF6n9v9VKLFGLBVz+G1LyL6GlcgZbIwhP89PPsp" # b7r6
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1ptqyz5C3YCcMgh3LUbXtjeS1rIZ5/6RHnH7D93Nqf" # 1password id_ed25519_b7r6
    ];
  };
}
