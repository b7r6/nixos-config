# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                             // hypermodern // nixos // modules
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
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{ lib, ... }: {
  imports = [
    # ── Core system (always-on) ──

    ./base.nix
    ./nix.nix
    ./packages.nix
    ./greetd.nix
    ./kernel.nix
    ./secrets.nix
    ./state.nix
    ../flake/registry/nixos.nix
    ../flake/registry/nixos-users.nix

    # ── Hardware (gated) ──

    ./bluetooth.nix
    ./nvidia.nix
    ./radeon.nix
    ./usb.nix

    # ── Networking ──

    ./network.nix
    ./network-manager.nix
    ../flake/coredns/nixos.nix
    ./reverse-proxy.nix
    ./oauth2-proxy.nix

    # ── Virtualization & containers (gated) ──

    ./docker.nix
    ./libvirt.nix

    # ── Services (gated) ──

    ../flake/attic/nixos-node.nix
    ../flake/attic/nixos.nix
    ../flake/backup/nixos.nix
    ../flake/media/nixos-dropbox.nix
    ../flake/media/nixos-pinchflat.nix
    ../flake/media/nixos-torrents.nix
    ../flake/media/nixos.nix
    ../flake/nativelink/nixos.nix
    ./clickhouse.nix
    ./otel.nix
    ./postgres.nix
    ./rayfish.nix
    ./rclone-mount.nix
    ./registry.nix
    ./searxng.nix
    ./supabase-native.nix
    ./supabase.nix

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
  # Firewall ON fleet-wide (the module default). tailscale0 is trusted, so this
  # never blocks tailnet/SSH — it just closes the PUBLIC interfaces and makes the
  # per-service interfaces.tailscale0.allowedTCPPorts rules actually ENFORCE the
  # "tailnet-only" posture (they're no-ops when the firewall is off). A host that
  # genuinely needs the firewall off sets hyper-modern-nixos.network.firewall.enable
  # = false explicitly. Public exposure goes through tailscale serve/funnel, not
  # by opening ports here (see network.nix).
  hyper-modern-nixos.network = {
    enable = true;
    tailnet.domain = "osiris-walleye.ts.net";
    useBackupResolver = true;
  };

  # ── Fleet-wide R2 mounts ────────────────────────────────────────────────────
  # Every host that imports this module mounts the shared /mnt/r2/common and its
  # own /mnt/r2/<hostname> off the straylight-r2 `host-mount` bucket. The module
  # self-wires the rclone.conf agenix secret, so there's nothing per-host to
  # declare. mkDefault so an individual host can still cleanly opt out. (test-vm
  # imports only the wayland module, not this one, so it's unaffected.)
  hyper-modern-nixos.rcloneMount.enable = lib.mkDefault true;
}
