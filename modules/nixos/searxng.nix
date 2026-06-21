# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // searxng
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Self-hosted SearXNG metasearch, OFF BY DEFAULT. A privacy-maxed config:
#   - no logging / no metrics retention, image proxy on, no external bangs
#   - results API (json/csv/rss) enabled so it's scriptable / usable as an
#     LLM web-search backend
#   - a broad engine set with the slow/loggy ones trimmed
#   - bound tailnet + loopback only (uwsgi http socket), not the open internet
#
# The secret signing key (server.secret_key) is REQUIRED and comes from an
# agenix env file as $SEARXNG_SECRET (referenced in settings via $VAR). Generate:
#   openssl rand -hex 32   ->   SEARXNG_SECRET=<that>
# stored as agenix machines/searxng-env.age and wired by the host.
{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.searxng;
in
{
  options.hyper-modern-nixos.searxng = {
    enable = lib.mkEnableOption "SearXNG metasearch (off by default)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Port SearXNG (uwsgi http) listens on.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        uwsgi bind address. Defaults to loopback. For tailnet access set this to
        "0.0.0.0" (binding the tailscale0 IP directly races boot) and leave
        openTailnet on — the firewall (ON fleet-wide) opens the port ONLY on
        tailscale0, so the broad bind is not publicly exposed. To reach SearXNG
        off-tailnet, front it with `tailscale serve` rather than opening a public
        firewall port.
      '';
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:${toString cfg.port}/";
      description = "Public base URL (used by SearXNG for absolute links).";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/searxng-env";
      description = "agenix env file providing SEARXNG_SECRET (the signing key).";
    };

    openTailnet = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the SearXNG port on tailscale0 only.";
    };

    limiter = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the bot-detection rate limiter. OFF by default: this is a
        private/tailnet instance and the limiter blocks scripted/JSON API use.
        Turn ON only if exposing the instance to the public internet.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.searx = {
      enable = true;
      # package defaults to pkgs.searxng upstream — no need to set it.
      redisCreateLocally = true; # valkey for the rate limiter + caching
      inherit (cfg) environmentFile;
      configureUwsgi = true;

      uwsgiConfig = {
        # http (not http-socket) so it speaks HTTP directly; behind a reverse
        # proxy later you'd switch to a unix socket.
        http = "${cfg.listenAddress}:${toString cfg.port}";
        disable-logging = true;
      };

      # ── settings.yml (privacy-maxed) ──────────────────────────────────────────
      settings = {
        general = {
          instance_name = "ono-sendai // search";
          # No "donate"/contact noise; don't leak engine errors to users.
          donation_url = false;
          enable_metrics = false;
        };

        server = {
          inherit (cfg) port;
          bind_address = cfg.listenAddress;
          base_url = cfg.baseUrl;
          secret_key = "$SEARXNG_SECRET"; # from environmentFile
          image_proxy = true; # proxy result images (no direct upstream fetches)
          method = "GET";
          # Private/tailnet instance: the limiter + public_instance botdetection
          # are PUBLIC-abuse defenses that just block our own scripted/JSON API
          # calls here. Off so the json/csv/rss API is freely usable on the
          # tailnet (flip `limiter` on only if this is ever exposed publicly).
          inherit (cfg) limiter;
          public_instance = false;
        };

        search = {
          safe_search = 0;
          autocomplete = "duckduckgo"; # suggestions without leaking to Google
          favicon_resolver = "duckduckgo";
          default_lang = "en";
          # Results API on — scriptable + usable as an LLM web-search backend.
          formats = [
            "html"
            "json"
            "csv"
            "rss"
          ];
        };

        ui = {
          static_use_hash = true;
          default_theme = "simple";
          theme_args.simple_style = "dark";
          infinite_scroll = true;
          search_on_category_select = true;
          hotkeys = "vim";
        };

        # No outgoing request fingerprint leakage beyond what engines need.
        outgoing = {
          request_timeout = 5.0;
          max_request_timeout = 12.0;
          pool_connections = 100;
          pool_maxsize = 20;
          enable_http2 = true;
        };

        # Trim engines that are slow/loggy/broken by default; keep a strong set.
        engines = lib.mapAttrsToList (name: settings: { inherit name; } // settings) {
          "duckduckgo".disabled = false;
          "brave".disabled = false;
          "startpage".disabled = false;
          "wikipedia".disabled = false;
          "github".disabled = false;
          "hackernews".disabled = false;
          "arch linux wiki".disabled = false;
          "nixos wiki".disabled = false;
          # noisy/slow defaults off:
          "google".disabled = true;
          "bing".disabled = true;
        };
      };

      limiterSettings = {
        real_ip = {
          x_for = 1;
          ipv4_prefix = 32;
          ipv6_prefix = 56;
        };
        botdetection.ip_limit = {
          filter_link_local = true;
          link_token = true;
        };
      };
    };

    networking.firewall.interfaces = lib.mkIf cfg.openTailnet {
      tailscale0.allowedTCPPorts = [ cfg.port ];
    };
  };
}
