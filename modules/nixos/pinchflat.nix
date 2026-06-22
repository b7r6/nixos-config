# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // pinchflat
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Pinchflat — self-hosted yt-dlp media manager (Elixir/Phoenix), OFF BY DEFAULT.
# You define channels/playlists as "sources" with download rules and it pulls
# new content on a schedule; also does one-off URL downloads. Web UI on :8945.
#
# Packaging: oci-containers (docker) wrapping the official image, but pulled
# from the FLEET zot registry (registry.sju1.s4.gl), not ghcr — so the image is
# R2-backed and reproducible from our own infra. Mirror a new tag with:
#   skopeo copy --policy <insecure> --override-os linux --override-arch amd64 \
#     docker://ghcr.io/kieraneglin/pinchflat:<tag> \
#     docker://registry.sju1.s4.gl/kieraneglin/pinchflat:<tag>
#
# Two dirs (Pinchflat's container contract):
#   /config    → SQLite DB + app state   (we map cfg.configDir; authoritative)
#   /downloads → media output            (we map cfg.downloadDir; default the
#                shared /var/lib/media so Navidrome/Jellyfin + our tag pipeline
#                see what Pinchflat fetches)
#
# Exposure: tailnet-only. The fleet firewall trusts tailscale0, and we open the
# port there explicitly. NOT fronted by nginx here (add a reverseProxy.services
# entry on the host if you want a vhost + TLS — note: heavy websockets).
{
  config,
  lib,
  ...
}:
let
  cfg = config.hyper-modern-nixos.pinchflat;
in
{
  options.hyper-modern-nixos.pinchflat = {
    enable = lib.mkEnableOption "Pinchflat yt-dlp media manager (oci container, off by default)";

    image = lib.mkOption {
      type = lib.types.str;
      default = "registry.sju1.s4.gl/kieraneglin/pinchflat:v2025.6.6-cffi";
      description = ''
        Pinchflat container image (pinned tag from the fleet zot registry). The
        `-cffi` tag is our thin overlay adding curl_cffi to the system Python so
        the bundled yt-dlp gains browser impersonation — required for reliable
        SoundCloud extraction. Built from packages/pinchflat-image/Dockerfile.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8945;
      description = "Host port for the Pinchflat web UI (container listens on 8945).";
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/pinchflat/config";
      description = "Host dir bind-mounted to /config (SQLite DB + app state). Authoritative state.";
    };

    downloadDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/media";
      description = ''
        Host dir bind-mounted to /downloads. Defaults to the shared media root so
        Pinchflat's output lands alongside the Navidrome/Jellyfin library and our
        tagging pipeline can sweep it.
      '';
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = config.time.timeZone or "UTC";
      description = "TZ passed to the container (IANA format).";
    };

    workerConcurrency = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "yt-dlp workers per queue (YT_DLP_WORKER_CONCURRENCY). Drop to 1 if IP-limited.";
    };

    openTailnet = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the Pinchflat port on tailscale0 only.";
    };

    extraEnvironment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra env vars for the container (e.g. BASIC_AUTH_USERNAME/PASSWORD).";
    };
  };

  config = lib.mkIf cfg.enable {
    # /config is irreplaceable app state (sources, rules, history) → authoritative
    # (restic-backed + impermanence-persisted via the state registry). The
    # download dir is declared by whatever owns it (e.g. the media module).
    hyper-modern-nixos.state.dirs.pinchflat = {
      path = cfg.configDir;
      class = "authoritative";
    };

    # Ensure the host dirs exist before the container starts.
    systemd.tmpfiles.rules = [
      "d ${cfg.configDir}   0755 root root - -"
      "d ${cfg.downloadDir} 0755 root root - -"
    ];

    # Use docker as the OCI backend (the fleet enables docker, not podman;
    # oci-containers otherwise defaults to podman and conflicts with docker.nix).
    virtualisation.oci-containers.backend = "docker";

    virtualisation.oci-containers.containers.pinchflat = {
      image = cfg.image;
      # Pull the pinned tag from zot; never auto-upgrade silently.
      pull = "missing";
      ports = [ "${toString cfg.port}:8945" ];
      volumes = [
        "${cfg.configDir}:/config"
        "${cfg.downloadDir}:/downloads"
      ];
      environment = {
        TZ = cfg.timezone;
        LOG_LEVEL = "info";
        YT_DLP_WORKER_CONCURRENCY = toString cfg.workerConcurrency;
      }
      // cfg.extraEnvironment;
    };

    networking.firewall.interfaces = lib.mkIf cfg.openTailnet {
      tailscale0.allowedTCPPorts = [ cfg.port ];
    };
  };
}
