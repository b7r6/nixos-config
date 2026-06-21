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
      inherit (cfg) credentialsFile;
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
        rpc-authentication-required = true;
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
      host = "0.0.0.0"; # bound broad; exposure gated by the tailnet firewall below
    };

    networking.firewall.interfaces = lib.mkIf cfg.openTailnet {
      tailscale0.allowedTCPPorts = [ cfg.floodPort ];
    };
  };
}
