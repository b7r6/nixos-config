# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // hyper-modern-nixos // reverse-proxy
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# nginx reverse proxy + internal ACME, OFF BY DEFAULT. The fleet's vhost router:
# services bind loopback, nginx terminates TLS on their logical names
# (<sub>.<dc>.s4.gl) with REAL Let's Encrypt certs via DNS-01 against s4.gl
# (Njalla). This replaces `tailscale serve`'s limits (one cert/node, no vhosts).
# See docs/src/architecture/networking.md (Layer 2).
#
# Split-horizon recap: CoreDNS already resolves <sub>.<dc>.s4.gl to this host's
# tailnet/LAN IP (Layer 1), so a client hits nginx here over the tailnet/LAN;
# nginx proxies to the loopback service. The cert is a real public-CA cert (s4.gl
# is a real domain), so no custom CA to distribute — browsers/clients just trust
# it. DNS-01 (not HTTP-01) because the names never face the public internet.
#
# A WILDCARD cert (*.<dc>.s4.gl) covers every internal vhost from one issuance.
{
  config,
  lib,
  flake ? null,
  ...
}:
let
  cfg = config.hyper-modern-nixos.reverseProxy;
  topo = config.hyper-modern-nixos.topology;

  inherit (lib)
    mkOption
    mkEnableOption
    types
    mapAttrs'
    nameValuePair
    ;

  # The internal zone this host fronts vhosts under, e.g. sju1.s4.gl.
  zone = "${cfg.dc}.${topo.registry.internalDomain}";

  # The wildcard cert name; one cert (*.<zone>) covers all vhosts.
  wildcardCert = "${zone}-wildcard";
in
{
  options.hyper-modern-nixos.reverseProxy = {
    enable = mkEnableOption "nginx reverse proxy + internal ACME (off by default)";

    dc = mkOption {
      type = types.str;
      default = "sju1";
      description = "DC subdomain whose zone this host fronts vhosts under (<dc>.<internalDomain>).";
    };

    acme = {
      email = mkOption {
        type = types.str;
        default = "admin@s4.gl";
        description = "Contact email for the ACME account.";
      };

      njallaTokenSecret = mkOption {
        type = types.nullOr types.str;
        default = "njalla-acme-token";
        description = ''
          agenix machine-secret NAME providing the Njalla API token as an env file
          (NJALLA_TOKEN=…) for lego's DNS-01. The module self-wires age.secrets.<name>.
          null = wire the ACME credentialsFile yourself.
        '';
      };

      staging = mkOption {
        type = types.bool;
        default = false;
        description = "Use Let's Encrypt STAGING (untrusted, high rate limits) — for first-run testing.";
      };
    };

    services = mkOption {
      default = { };
      description = ''
        Services to front. Attr name = the subdomain label (vhost becomes
        <name>.<dc>.<internalDomain>); each maps to a loopback upstream.
      '';
      example = lib.literalExpression ''
        {
          registry = { port = 5000; };           # → registry.sju1.s4.gl → 127.0.0.1:5000
          search   = { port = 8889; upstream = "127.0.0.1:8889"; };
        }
      '';
      type = types.attrsOf (
        types.submodule (
          { name, ... }: {
            options = {
              port = mkOption {
                type = types.nullOr types.port;
                default = null;
                description = "Loopback port of the upstream (shorthand for upstream = 127.0.0.1:<port>).";
              };
              upstream = mkOption {
                type = types.str;
                default = "127.0.0.1:${toString config.hyper-modern-nixos.reverseProxy.services.${name}.port}";
                defaultText = "127.0.0.1:\${port}";
                description = "host:port nginx proxies to.";
              };
              scheme = mkOption {
                type = types.str;
                default = "http";
                description = "Upstream scheme (http or https for TLS backends like kanidm).";
              };
              websockets = mkOption {
                type = types.bool;
                default = true;
                description = "Enable WebSocket upgrade headers.";
              };
              root = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Serve a STATIC directory instead of proxying. When set, the
                  vhost roots here (autoindex OFF — directory listing disabled,
                  which is what keeps the dropbox "unguessable, not crawlable")
                  and `upstream`/`port`/`websockets` are ignored.
                '';
              };
              maxBodySize = mkOption {
                type = types.str;
                default = "1m";
                description = ''
                  nginx client_max_body_size for this vhost. The default 1m is
                  fine for typical web UIs but FAR too small for OCI registry
                  pushes (multi-MB/GB image layers → HTTP 413). Set "0" to
                  disable the limit for a registry vhost, or a size like "2g".
                '';
              };
              extraProxyConfig = mkOption {
                type = types.lines;
                default = "";
                description = ''
                  Extra nginx directives injected into this vhost's proxy
                  location. Use for an OCI registry streaming large layer uploads
                  to a slow backend (e.g. R2-tiered stores): lift proxy_read_timeout /
                  proxy_send_timeout and turn off proxy_request_buffering, since
                  the default 60s proxy timeout yields 502 Bad Gateway mid-push
                  once a layer takes longer than a minute to stream.
                '';
              };
              protected = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Gate this service behind oauth2-proxy (Kanidm OIDC). Requires
                  hyper-modern-nixos.oauth2-proxy.enable = true on this host.
                  Adds auth_request + /oauth2/ locations to the vhost.
                '';
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.acme.njallaTokenSecret != null;
        message = ''
          reverseProxy.enable is true but acme.njallaTokenSecret is null. Internal
          TLS uses DNS-01 against s4.gl, which needs a Njalla API token (NJALLA_TOKEN)
          from an agenix env file — never the store. Set it or wire credentialsFile.
        '';
      }
    ];

    # Self-wire the Njalla token secret (root-owned; acme reads it as root).
    age.secrets = lib.mkIf (cfg.acme.njallaTokenSecret != null) {
      ${cfg.acme.njallaTokenSecret}.file =
        flake.self + "/secrets/agenix/machines/${cfg.acme.njallaTokenSecret}.age";
    };

    security.acme = {
      acceptTerms = true;
      defaults = {
        email = cfg.acme.email;
        dnsProvider = "njalla";
        # lego reads NJALLA_TOKEN from this env file (agenix runtime path).
        environmentFile = "/run/agenix/${cfg.acme.njallaTokenSecret}";
        # DNS-01: don't try to reach the names over HTTP.
        dnsResolver = "1.1.1.1:53";
      }
      // lib.optionalAttrs cfg.acme.staging {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory";
      };

      # One wildcard cert covers every internal vhost (both long and short forms).
      # Note: bare domains (sju1.s4.gl, s4.gl) are omitted — Let's Encrypt rejects
      # them as redundant with wildcards in the same request.
      certs.${wildcardCert} = {
        domain = "*.${zone}";
        extraDomainNames = [ "*.${topo.registry.internalDomain}" ];
        group = config.services.nginx.group;
      };
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      # Map for websocket upgrade (used by vhosts that enable it).
      appendHttpConfig = ''
        map $http_upgrade $connection_upgrade {
          default upgrade;
          "" close;
        }
      '';

      # stub_status for prometheus scraping (loopback only)
      statusPage = true;

      virtualHosts = mapAttrs' (
        sub: svc:
        nameValuePair "${sub}.${zone}" {
          serverAliases = [ "${sub}.${topo.registry.internalDomain}" ];
          forceSSL = true;
          useACMEHost = wildcardCert; # share the one wildcard cert
          # Per-vhost body cap; registries need this lifted for layer pushes.
          extraConfig = "client_max_body_size ${svc.maxBodySize};";
          locations."/" =
            if svc.root != null then
              {
                inherit (svc) root;
                extraConfig = "autoindex off;";
              }
            else
              {
                proxyPass = "${svc.scheme}://${svc.upstream}";
                proxyWebsockets = svc.websockets;
                extraConfig =
                  (lib.optionalString svc.protected ''
                    auth_request /oauth2/auth;
                    error_page 401 = /oauth2/sign_in;
                    auth_request_set $user $upstream_http_x_auth_request_user;
                    auth_request_set $email $upstream_http_x_auth_request_email;
                    proxy_set_header X-User $user;
                    proxy_set_header X-Email $email;
                  '')
                  + svc.extraProxyConfig;
              };

          # oauth2-proxy endpoints (only when this vhost is protected)
          locations."/oauth2/" = lib.mkIf svc.protected {
            proxyPass = "http://127.0.0.1:${toString config.hyper-modern-nixos.oauth2-proxy.port}/oauth2/";
            extraConfig = ''
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Auth-Request-Redirect $request_uri;
            '';
          };
          locations."/oauth2/auth" = lib.mkIf svc.protected {
            proxyPass = "http://127.0.0.1:${toString config.hyper-modern-nixos.oauth2-proxy.port}/oauth2/auth";
            extraConfig = ''
              internal;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Auth-Request-Redirect $request_uri;
            '';
          };
        }
      ) cfg.services;
    };

    # 80 (ACME/redirect) + 443 open on all interfaces (LAN + tailnet clients).
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
