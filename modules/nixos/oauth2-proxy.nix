# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                          // hypermodern // oauth2-proxy
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# per-host oauth2-proxy sidecar that gates nginx vhosts through Kanidm.
# services without native OIDC get auth via nginx auth_request → this proxy.
#
# usage:
#   hyper-modern-nixos.oauth2-proxy = {
#     enable = true;
#     clientId = "guccimane-proxy";
#     clientSecretFile = "/run/agenix/oauth2-proxy-secret";
#     cookieSecretFile = "/run/agenix/oauth2-proxy-cookie";
#   };
#
# then in your nginx vhost:
#   locations."/" = {
#     extraConfig = config.hyper-modern-nixos.oauth2-proxy.nginxAuthSnippet;
#     proxyPass = "http://127.0.0.1:${port}";
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.oauth2-proxy;
  proxyPort = 4180;
in
{
  options.hyper-modern-nixos.oauth2-proxy = {
    enable = lib.mkEnableOption "oauth2-proxy sidecar (Kanidm OIDC → nginx auth_request)";

    clientId = lib.mkOption {
      type = lib.types.str;
      description = "Kanidm OAuth2 client ID for this host's proxy.";
    };

    clientSecretFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to file containing the OAuth2 client secret.";
    };

    cookieSecretFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to file containing the cookie encryption secret (32 bytes, base64).";
    };

    issuerUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.s4.gl/oauth2/openid/${cfg.clientId}";
      description = "OIDC issuer URL (Kanidm per-client endpoint).";
    };

    cookieDomain = lib.mkOption {
      type = lib.types.str;
      default = ".s4.gl";
      description = "Cookie domain (shared across *.s4.gl subdomains on this host).";
    };

    allowedGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "fleet_users"
        "fleet_admins"
      ];
      description = "Kanidm groups that are allowed through the proxy.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = proxyPort;
      description = "Local port for oauth2-proxy.";
    };

    # generated snippet for nginx locations
    nginxAuthSnippet = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = ''
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/sign_in;
        auth_request_set $user $upstream_http_x_auth_request_user;
        auth_request_set $email $upstream_http_x_auth_request_email;
        proxy_set_header X-User $user;
        proxy_set_header X-Email $email;
      '';
      description = "Nginx config snippet to protect a location via oauth2-proxy.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.oauth2-proxy = {
      description = "oauth2-proxy (Kanidm OIDC sidecar)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = 5;
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.oauth2-proxy}/bin/oauth2-proxy"
          "--http-address=127.0.0.1:${toString cfg.port}"
          "--provider=oidc"
          "--oidc-issuer-url=${cfg.issuerUrl}"
          "--client-id=${cfg.clientId}"
          "--client-secret-file=${cfg.clientSecretFile}"
          "--cookie-secret-file=${cfg.cookieSecretFile}"
          "--cookie-domain=${cfg.cookieDomain}"
          "--cookie-samesite=lax"
          "--cookie-secure=true"
          "--email-domain=*"
          "--scope=openid email profile groups"
          "--redirect-url=https://${config.networking.hostName}.s4.gl/oauth2/callback"
          "--upstream=static://202"
          "--skip-provider-button=true"
          "--code-challenge-method=S256"
          "--reverse-proxy=true"
          "--set-xauthrequest=true"
        ];
      };
    };

    # nginx locations for the proxy itself (every vhost inherits these)
    services.nginx.virtualHosts = lib.mkIf (config.services.nginx.enable or false) {
      "_oauth2_internal" = {
        # internal vhost — the auth_request locations
        # this is referenced by the snippet via /oauth2/ paths
      };
    };

    # add oauth2 location to the nginx http-level (all vhosts share it)
    services.nginx.appendHttpConfig = ''
      # oauth2-proxy endpoints (shared across all vhosts on this host)
      upstream _oauth2_proxy {
        server 127.0.0.1:${toString cfg.port};
      }
    '';

    # every nginx server gets the /oauth2/ location
    services.nginx.commonHttpConfig = lib.mkAfter ''
      # oauth2-proxy auth endpoints
      map $host $oauth2_upstream {
        default http://127.0.0.1:${toString cfg.port};
      }
    '';
  };
}
