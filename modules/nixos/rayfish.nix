# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // rayfish
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#   "It belonged to her, now: whatever it was. Something that had never known
#    a coordinator, that answered to no console but its own."
#
# rayfish P2P mesh VPN (iroh), OFF BY DEFAULT. An INDEPENDENT fallback mesh: when
# the tailnet or its control plane is down, rayfish still forms — peers find each
# other over a DHT and hole-punch directly (relay fallback), no coordination
# server to be down. The point is out-of-band reach for boxes with NO IPMI.
#
# Coexists with Tailscale on the same host: our vendored fork (inputs.rayfish)
# remaps the v4 overlay off 100.64.0.0/10 (Tailscale's CGNAT block) onto
# 10.64.0.0/10, so both TUNs route without collision. IPv6 stays on 200::/7 (no
# clash with Tailscale's fd7a:115c::/48 ULA).
#
# ── self-operating (systemd) ─────────────────────────────────────────────────
#   rayfish.service          the daemon (`ray daemon`, root). Owns the TUN,
#                            installs routes, serves .ray DNS. On start it
#                            bootstraps and AUTO-ACTIVATES saved networks, so a
#                            host that is already a member reconnects on boot
#                            with no manual `ray up`.
#   rayfish-operator.service oneshot: grants `operator` UID access once the
#                            socket is live (day-to-day `ray` without sudo).
#   rayfish-enroll.service   oneshot, ONLY when joinKeyFile is set: a FRESH host
#                            self-joins the fallback mesh from a reusable invite
#                            key (agenix), the way tailscale-auth-key enrolls a
#                            box non-interactively. Guarded by a stamp so it runs
#                            exactly once and never re-joins; retries next boot
#                            until it succeeds.
#
# identity keys + signed rosters live under /var/lib/rayfish, classified
# `authoritative` → persisted across impermanence AND backed up to R2 (losing the
# identity = losing membership / a coordinator role; the enroll stamp rides with
# it, so a restored host does NOT re-enroll — the daemon just reconnects).
#
# n.b. EXPERIMENTAL, pre-1.0, unaudited upstream. Incubation posture only — this
# is a fallback, NOT a Tailscale replacement.
{
  flake,
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (flake) inputs;

  cfg = config.hyper-modern-nixos.rayfish;

  package =
    if cfg.package != null then
      cfg.package
    else
      inputs.rayfish.packages.${pkgs.stdenv.hostPlatform.system}.default;

  ray = "${package}/bin/ray";

  # Poll until the daemon's IPC socket answers (bounded), so oneshots ordered
  # After=rayfish.service don't race the daemon's startup.
  waitReady = ''
    for _ in $(seq 1 30); do
      ${ray} status >/dev/null 2>&1 && break
      sleep 1
    done
  '';

  enrollStamp = "${cfg.stateDir}/.enrolled";
in
{
  options.hyper-modern-nixos.rayfish = {
    enable = lib.mkEnableOption "rayfish P2P mesh VPN (iroh) — EXPERIMENTAL fallback mesh, off by default";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      defaultText = lib.literalExpression "inputs.rayfish.packages.\${system}.default";
      description = "rayfish package (the `ray` daemon+CLI). Defaults to the flake input for this host's arch.";
    };

    operator = lib.mkOption {
      type = lib.types.str;
      default = "b7r6";
      description = ''
        Local user granted operator access (runs `ray` without sudo), via the
        rayfish-operator oneshot (`ray set-operator`).
      '';
    };

    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      defaultText = lib.literalExpression "config.networking.hostName";
      description = "This node's hostname within the mesh (→ <hostname>.<network>.ray). Used at enroll.";
    };

    joinKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/agenix/rayfish-join-key";
      description = ''
        Path to a file holding a REUSABLE invite key (from `ray invite <net>
        --reusable`), never the store. When set, the rayfish-enroll oneshot makes
        a fresh host self-join the fallback mesh non-interactively (mirrors
        network.tailscale.authKeyFile). Wire it yourself via age.secrets. null =
        no auto-enroll (join by hand with `ray join`).
      '';
    };

    networkAlias = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional local alias (`ray join --name`) for the enrolled network.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/rayfish";
      description = ''
        Daemon state directory: identity key + signed network rosters (+ the
        enroll stamp). Declared `authoritative`, so it is persisted and backed up.
        LOSING THIS = losing mesh membership and any coordinator identity.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open UDP 41383 (rayfish's fixed direct-path port). Only a direct-path
        OPTIMISATION: hole-punching (UPnP/NAT-PMP) and relay fallback work without
        it. A manual forward benefits only ONE node per LAN.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # /dev/net/tun for the overlay device (usually auto-loaded; be explicit).
    boot.kernelModules = [ "tun" ];

    # identity + rosters are irreplaceable → persist across impermanence + back up.
    hyper-modern-nixos.state.dirs.rayfish = {
      path = cfg.stateDir;
      class = "authoritative";
    };

    environment.systemPackages = [ package ];

    systemd.services.rayfish = {
      description = "rayfish P2P mesh VPN (iroh)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        # Runs as root: creates the TUN, installs routes, manages .ray DNS. On
        # start it auto-activates saved networks (no manual `ray up` on reboot).
        ExecStart = "${ray} daemon";
        Restart = "on-failure";
        RestartSec = 5;

        # /var/lib/rayfish (0700 root) + /var/log/rayfish for the rolling logs.
        StateDirectory = "rayfish";
        StateDirectoryMode = "0700";
        LogsDirectory = "rayfish";
      };
    };

    # ── operator grant (oneshot) ──────────────────────────────────────────────
    systemd.services.rayfish-operator = {
      description = "rayfish: grant operator access to ${cfg.operator}";
      after = [ "rayfish.service" ];
      requires = [ "rayfish.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${waitReady}
        ${ray} set-operator ${lib.escapeShellArg cfg.operator} || true
      '';
    };

    # ── fresh-host auto-enroll (oneshot; only with a join key) ─────────────────
    # Idempotent: skipped once the stamp exists (which is backed up with the
    # state dir), so a restored host reconnects via the daemon instead of
    # re-joining. If the join fails (key expired, coordinator unreachable) the
    # stamp is NOT written, so it retries on the next boot.
    systemd.services.rayfish-enroll = lib.mkIf (cfg.joinKeyFile != null) {
      description = "rayfish: self-join the fallback mesh (reusable key)";
      after = [
        "rayfish.service"
        "network-online.target"
      ];
      requires = [ "rayfish.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.ConditionPathExists = "!${enrollStamp}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${waitReady}
        if ${ray} join "$(cat ${cfg.joinKeyFile})" \
            --hostname ${lib.escapeShellArg cfg.hostname} \
            --auto-accept-firewall \
            ${
              lib.optionalString (cfg.networkAlias != null) "--name ${lib.escapeShellArg cfg.networkAlias}"
            }; then
          touch ${enrollStamp}
        fi
      '';
    };

    networking.firewall.allowedUDPPorts = lib.mkIf cfg.openFirewall [ 41383 ];
  };
}
