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
{ lib, flake, ... }: {
  imports = [
    # ── Core system (always-on) ──

    ./base.nix
    ./nix.nix
    ./packages.nix
    ./greetd.nix
    ./kernel.nix
    ./performance.nix
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
    # nativelink's NixOS module lives in the FORK (the fork owns its ops);
    # the shim wires OUR fleet topology, telemetry, and state registry.
    flake.inputs.nativelink-nix.nixosModules.nativelink
    ../flake/nativelink/shim.nix
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

  # ── Fleet-wide Nix binary cache (replaces the attic replica) ────────────────
  # Every host runs a local nativelink nix_cache on :50071, populated by the
  # nl-watch-store fanotify daemon and consulted first as a substituter (the
  # module injects it when enabled). The signing key is a GLOBAL agenix secret and its
  # public half is trusted fleet-wide (nix.nix), so any host can both push to and
  # substitute from its own signed cache. mkDefault so a host can opt out
  # (`hyper-modern-nixos.nativelink.nixCache.enable = lib.mkForce false`), e.g.
  # a disk-constrained box or the test-vm. Rollout is per-host: this codifies the
  # default; each host adopts it on its next rebuild.
  age.secrets.nativelink-nix-cache-key.file =
    ../../secrets/agenix/machines/nativelink-nix-cache-key.age;

  hyper-modern-nixos.nativelink.nixCache = {
    enable = lib.mkDefault true;
    watchStore = lib.mkDefault true;
    signingKeyFile = lib.mkDefault "/run/agenix/nativelink-nix-cache-key";
  };

  # ── attic retired fleet-wide ────────────────────────────────────────────────
  # Superseded by the nativelink nix_cache above. The attic modules stay imported
  # (rollback path) but no host runs atticd, its watch-store, or its substituter.
  # Forced off centrally rather than per-host so the switch is one line; prune the
  # now-inert per-host `attic-node` blocks as each host is rolled onto nativelink.
  hyper-modern-nixos.attic-node.enable = lib.mkForce false;
}
