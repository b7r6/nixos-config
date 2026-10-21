# railgun — identity: Kanidm at auth.s4.gl, the fleet's OIDC provider.
#
# Ported from watchtower (sold 2026-10-07), which ran the same IdP for the same
# names. Fresh database: persons and groups come from the user registry
# (hyper-modern-nixos.identity.kanidm, users.dhall), the two OIDC clients are
# declared here with secrets that already live in agenix.
#
#   auth.s4.gl   nginx (wildcard cert) → kanidmd on 127.0.0.1:8443 (self-signed
#                loopback TLS; kanidmd refuses to serve plain HTTP)
#   git.s4.gl    Forgejo: "Sign in with kanidm" (source registered by the
#                forgejo-auth-kanidm oneshot below; Forgejo keeps auth sources
#                in its database, not app.ini, so this makes it declarative)
#   grafana.s4.gl  generic_oauth; Admin for grafana_admins, Viewer otherwise
#
# First login for a person: they need a credential (passkey or password).
# Issue a one-time enrolment link as idm_admin:
#   KANIDM_PASSWORD=$(sudo cat /run/agenix/kanidm-admin-password) \
#     kanidm login -H https://auth.s4.gl -D idm_admin
#   kanidm person credential create-reset-token <name> -H https://auth.s4.gl -D idm_admin
{
  config,
  lib,
  pkgs,
  ...
}:
let
  forgejo = config.services.forgejo;
  issuer = "https://auth.s4.gl";
  secret = name: owner: {
    file = ../../../secrets/agenix/machines/${name}.age;
    inherit owner;
    mode = "0400";
  };
  oidcScopes = [
    "openid"
    "email"
    "profile"
    "groups"
  ];
in
{
  # persons + groups (+ forgejo scope map) provisioned from the user registry
  hyper-modern-nixos.identity.kanidm = true;

  services.kanidm = {
    package = pkgs.kanidm_1_11.withSecretProvisioning; # 1.8–1.10 are end-of-life in nixpkgs
    server.enable = true;
    server.settings = {
      origin = issuer;
      domain = "s4.gl"; # the WebAuthn relying-party id: passkeys bind to it
      bindaddress = "127.0.0.1:8443";
      ldapbindaddress = null;
      log_level = "info";
      role = "WriteReplica";
      tls_chain = "/var/lib/kanidm/tls/chain.pem";
      tls_key = "/var/lib/kanidm/tls/key.pem";
      # consistent daily snapshots; restic (./default.nix) ships them to R2
      online_backup = {
        path = "/var/lib/kanidm/backups/";
        schedule = "0 2 * * *";
        versions = 7;
      };
    };

    provision = {
      enable = true;
      adminPasswordFile = "/run/agenix/kanidm-admin-password";
      idmAdminPasswordFile = "/run/agenix/kanidm-admin-password";

      systems.oauth2.forgejo = {
        displayName = "// straylight // git //";
        originUrl = "https://git.s4.gl/user/oauth2/kanidm/callback";
        originLanding = "https://git.s4.gl/";
        basicSecretFile = "/run/agenix/kanidm-forgejo-secret";
        preferShortUsername = true;
        allowInsecureClientDisablePkce = true; # Forgejo's OIDC client sends no PKCE
        # scopeMaps: forgejo_users, from the identity module
      };

      systems.oauth2.grafana = {
        displayName = "// straylight // grafana //";
        originUrl = "https://grafana.s4.gl/login/generic_oauth";
        originLanding = "https://grafana.s4.gl/";
        basicSecretFile = "/run/agenix/kanidm-grafana-secret";
        preferShortUsername = true;
        scopeMaps = {
          fleet_users = oidcScopes;
          fleet_admins = oidcScopes;
          grafana_admins = oidcScopes;
        };
      };
    };
  };

  # self-signed cert for the loopback listener (nginx holds the real one)
  systemd.services.kanidm-tls-init = {
    description = "self-signed TLS for kanidmd's loopback listener";
    before = [ "kanidm.service" ];
    requiredBy = [ "kanidm.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "kanidm";
      Group = "kanidm";
      StateDirectory = "kanidm/tls";
      RemainAfterExit = true;
    };
    path = [ pkgs.openssl ];
    script = ''
      if [ ! -f /var/lib/kanidm/tls/key.pem ]; then
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
          -keyout /var/lib/kanidm/tls/key.pem -out /var/lib/kanidm/tls/chain.pem \
          -days 3650 -nodes -subj "/CN=localhost"
      fi
      chmod 0400 /var/lib/kanidm/tls/key.pem # kanidmd warns unless owner-read-only
    '';
  };

  hyper-modern-nixos.reverseProxy.services.auth = {
    upstream = "127.0.0.1:8443";
    scheme = "https";
  };

  # one secret per consumer: kanidm provisions the client, the app presents it
  age.secrets = {
    kanidm-admin-password = secret "kanidm-admin-password" "kanidm";
    kanidm-forgejo-secret = secret "kanidm-forgejo-secret" "kanidm";
    kanidm-grafana-secret = secret "kanidm-grafana-secret" "kanidm";
    forgejo-oauth-secret = secret "kanidm-forgejo-secret" forgejo.user;
    grafana-oauth-secret = secret "kanidm-grafana-secret" "grafana";
  };

  # ── Forgejo: accounts come from Kanidm ─────────────────────────────────────
  # Registration stays closed to everyone except Kanidm logins. The username is
  # the local part of the Kanidm mail address (users.dhall keeps it equal to the
  # account name), and ACCOUNT_LINKING=auto attaches that login to an existing
  # Forgejo account of the same name: b7r6's first Kanidm sign-in lands in the
  # existing b7r6 admin account. Local sign-in stays as the break-glass path.
  services.forgejo.settings = {
    service = {
      DISABLE_REGISTRATION = lib.mkForce false;
      ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
      SHOW_REGISTRATION_BUTTON = false;
    };
    oauth2_client = {
      ENABLE_AUTO_REGISTRATION = true;
      ACCOUNT_LINKING = "auto";
      USERNAME = "email";
      OPENID_CONNECT_SCOPES = "openid email profile";
      UPDATE_AVATAR = false;
    };
  };

  systemd.services.forgejo-auth-kanidm = {
    description = "register Kanidm as Forgejo's OpenID Connect login source";
    # Forgejo fetches the discovery document while registering the source, so
    # Kanidm must be answering through nginx first (a restart mid-activation
    # otherwise yields a 502 and a failed unit).
    after = [
      "forgejo.service"
      "kanidm.service"
      "nginx.service"
    ];
    requires = [ "forgejo.service" ];
    wants = [
      "kanidm.service"
      "nginx.service"
    ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.gawk
      pkgs.curl
    ];
    # re-run when the client secret changes
    restartTriggers = [ config.age.secrets.forgejo-oauth-secret.file ];
    environment = {
      USER = forgejo.user;
      HOME = forgejo.stateDir;
      FORGEJO_WORK_DIR = forgejo.stateDir;
      FORGEJO_CUSTOM = forgejo.customDir;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = forgejo.user;
      Group = forgejo.group;
      WorkingDirectory = forgejo.stateDir;
    };
    script = ''
      exe=${lib.getExe forgejo.package}
      discovery=${issuer}/oauth2/openid/forgejo/.well-known/openid-configuration
      for _ in $(seq 60); do
        curl -fsS -o /dev/null --resolve auth.s4.gl:443:127.0.0.1 "$discovery" && break
        sleep 2
      done
      args=(
        --name kanidm
        --provider openidConnect
        --key forgejo
        --secret "$(cat /run/agenix/forgejo-oauth-secret)"
        --auto-discover-url "$discovery"
        --scopes openid --scopes email --scopes profile
        --skip-local-2fa
      )
      id=$("$exe" admin auth list | awk '$2 == "kanidm" { print $1 }')
      if [ -z "$id" ]; then
        "$exe" admin auth add-oauth "''${args[@]}"
        echo "kanidm login source added"
      else
        "$exe" admin auth update-oauth --id "$id" "''${args[@]}"
        echo "kanidm login source $id updated"
      fi
    '';
  };

  # ── Grafana ────────────────────────────────────────────────────────────────
  services.grafana.settings."auth.generic_oauth" = {
    enabled = true;
    name = "Kanidm";
    icon = "signin";
    client_id = "grafana";
    client_secret = "$__file{/run/agenix/grafana-oauth-secret}";
    scopes = lib.concatStringsSep " " oidcScopes;
    auth_url = "${issuer}/ui/oauth2";
    token_url = "${issuer}/oauth2/token";
    api_url = "${issuer}/oauth2/openid/grafana/userinfo";
    use_pkce = true;
    allow_sign_up = true;
    login_attribute_path = "preferred_username";
    # Kanidm's groups claim carries SPNs (name@domain); accept the bare name too
    # (JMESPath binds && tighter than ||, hence the parentheses)
    role_attribute_path = "(contains(groups[*], 'grafana_admins@s4.gl') || contains(groups[*], 'grafana_admins')) && 'Admin' || 'Viewer'";
  };

  # Kanidm's own daily snapshots join the hourly restic run.
  hyper-modern-nixos.backup.paths = [ "/var/lib/kanidm/backups" ];
}
