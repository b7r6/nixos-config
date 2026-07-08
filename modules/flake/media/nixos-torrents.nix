# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                             // hyper-modern-nixos // torrents
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# transmission daemon + flood web UI, OFF BY DEFAULT.
#
#   transmission : the daemon. RPC bound to LOOPBACK only (flood talks to it
#                  locally). Peer port opened for connectivity. Traffic follows
#                  the host's default route — so when the box uses the Mullvad
#                  Miami exit node, torrents exit Miami (no separate killswitch,
#                  per the chosen posture).
#   flood        : a modern web UI for transmission, served on the TAILNET
#                  (firewall opens it on tailscale0 only). Log in and point it at
#                  the transmission RPC (127.0.0.1 + the rpc credentials).
#
# RPC password (REQUIRED): transmission reads rpc-password from credentialsFile
# (an agenix JSON file: {"rpc-password":"…"}). transmission rewrites it to a
# salted hash on first start. Stored as agenix machines/transmission-rpc.age.
#
# ── ssoGated ────────────────────────────────────────────────────────────────
# When an EXTERNAL gate fronts flood (oauth2-proxy → Kanidm on nginx), set
# `ssoGated = true` to authenticate the human ONCE at the perimeter instead of
# again at flood's own login:
#
#   - flood runs with `--auth none` — no flood login screen; it connects
#     DIRECTLY to transmission over loopback using the built-in configUser.
#   - transmission RPC auth is dropped: the 127.0.0.1 bind is the boundary (flood
#     is the sole client and is itself Kanidm-gated), so no rpc-password travels
#     anywhere — no store/cmdline exposure, no credentialsFile needed.
#   - flood binds LOOPBACK and the tailnet port stays CLOSED, so nobody can reach
#     flood directly on tailscale0 and skip the SSO gate. nginx (same host)
#     proxies 127.0.0.1:floodPort under the protected vhost.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.torrents;
in
{
  options.hyper-modern-nixos.torrents = {
    enable = lib.mkEnableOption "transmission + flood torrent stack (off by default)";

    ssoGated = lib.mkEnableOption ''
      flood single-sign-on mode. Disables flood's own login (--auth none) and
      transmission's RPC auth (loopback bind is the boundary), binds flood to
      loopback, and keeps the tailnet port closed. Use when oauth2-proxy/Kanidm
      fronts flood on nginx so users authenticate ONCE at the perimeter
    '';

    downloadDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/transmission/Downloads";
      description = "Completed-downloads directory.";
    };

    peerPort = lib.mkOption {
      type = lib.types.port;
      default = 51413;
      description = "transmission peer (BT) port. Opened on all interfaces for connectivity.";
    };

    rpcPort = lib.mkOption {
      type = lib.types.port;
      default = 9091;
      description = "transmission RPC port (loopback only; flood connects here).";
    };

    floodPort = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "flood web UI port (opened on tailscale0 only).";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/transmission-rpc";
      description = ''
        agenix JSON file with secret transmission settings, at minimum
        {"rpc-password":"…"}. transmission salts/hashes it on first start.
      '';
    };

    openTailnet = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the flood UI port on tailscale0 only.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.transmission = {
      enable = true;
      package = pkgs.transmission_4;
      # ssoGated drops RPC auth (loopback bind is the boundary) — no credentials.
      credentialsFile = lib.mkIf (!cfg.ssoGated) cfg.credentialsFile;
      # Open the peer port in the firewall for inbound BT connectivity.
      openPeerPorts = true;

      settings = {
        download-dir = cfg.downloadDir;
        incomplete-dir = "${cfg.downloadDir}/.incomplete";
        incomplete-dir-enabled = true;

        # ── RPC: loopback only; flood is the only client ──
        rpc-enabled = true;
        rpc-bind-address = "127.0.0.1";
        rpc-port = cfg.rpcPort;
        # ssoGated: loopback bind + external Kanidm gate is the boundary, so no
        # per-request RPC auth (flood connects with --auth none, no password).
        rpc-authentication-required = !cfg.ssoGated;
        rpc-username = "transmission";
        # rpc-password comes from credentialsFile (never the store).
        rpc-whitelist-enabled = false; # loopback-only bind already gates it
        rpc-host-whitelist-enabled = false;

        # ── peers ──
        peer-port = cfg.peerPort;
        peer-port-random-on-start = false;
        # Be a good citizen but don't throttle hard.
        ratio-limit-enabled = false;
        encryption = 2; # require encryption
        dht-enabled = true;
        pex-enabled = true;
        utp-enabled = true;

        # umask so flood (separate user) can read completed files if needed.
        umask = 2;
        message-level = 1;
      };
    };

    # transmission's systemd sandbox (mount namespacing) requires the
    # incomplete-dir to EXIST before start — it only auto-creates download-dir.
    # Pre-create it (and the download-dir) owned by transmission via tmpfiles.
    systemd.tmpfiles.rules = [
      "d ${cfg.downloadDir} 0770 transmission transmission - -"
      "d ${cfg.downloadDir}/.incomplete 0770 transmission transmission - -"
    ];

    services.flood = {
      enable = true;
      port = cfg.floodPort;
      # ssoGated: bind LOOPBACK (nginx fronts it; no tailnet bypass of the SSO
      # gate). Otherwise bind broad so flood is reachable on the tailnet (binding
      # the tailscale0 IP directly races boot); the firewall opens floodPort ONLY
      # on tailscale0 — see below.
      host = if cfg.ssoGated then "127.0.0.1" else "0.0.0.0";
      # ssoGated: disable flood's own login and connect straight to transmission
      # over loopback, so the Kanidm perimeter is the single auth point.
      extraArgs = lib.mkIf cfg.ssoGated [
        "--auth"
        "none"
        "--trurl"
        "http://127.0.0.1:${toString cfg.rpcPort}/transmission/rpc"
        "--truser"
        "transmission"
        # transmission RPC auth is disabled in ssoGated mode (loopback bind is the
        # boundary), so there is no password — but flood's --auth=none schema still
        # REQUIRES configUser.password to be a string, so pass an empty one or flood
        # dies at startup with a ZodError ("configUser.password Required").
        "--trpass"
        ""
      ];
    };

    # Tailnet exposure only when NOT ssoGated — a direct tailscale0 port would
    # let clients reach flood without passing the oauth2-proxy/Kanidm gate.
    networking.firewall.interfaces = lib.mkIf (cfg.openTailnet && !cfg.ssoGated) {
      tailscale0.allowedTCPPorts = [ cfg.floodPort ];
    };
  };
}
