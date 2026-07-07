{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
  ];

  # ── Tailscale safety net ────────────────────────────────────────────────────
  # Declarative enrollment so the tailscaled restart on switch can't strand this
  # remote box off the tailnet (the deploy itself runs over the tailnet).
  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # CoreDNS as this node's own resolver (resolves *.sju1.s4.gl — e.g. the
  # nativelink scheduler/CAS FQDNs — which MagicDNS can't; tailscale stops
  # managing resolv.conf). See docs/architecture/networking.md.
  hyper-modern-nixos.coredns.enable = true;

  # ── NativeLink: x86_64 CAS shard (weight 4) + worker ────────────────────────
  # From the typed Dhall fleet (out/guccimane.json): a CAS shard server + an
  # x86_64 worker dialing watchtower's scheduler over the tailnet.
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;
  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = "guccimane";
    openFirewall = true;
    r2 = {
      enable = true;
      accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
      bucket = "straylight-nativelink-cas";
      environmentFile = "/run/agenix/nativelink-r2-env";
    };
  };

  hyper-modern-nixos.hyper-wayland = {
    enable = true;
  };

  hyper-modern-nixos.nvidia = {
    enable = true;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.enableRedistributableFirmware = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Bluetooth management GUI
  services.blueman.enable = true;

  # CPU and system optimizations
  boot.kernelParams = [ "pcie_aspm=off" ];
  powerManagement.cpuFreqGovernor = "performance";
  hardware.cpu.amd.updateMicrocode = true;

  networking.hostName = "guccimane";
  networking.networkmanager.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.thermald.enable = true;

  security.sudo.wheelNeedsPassword = false;

  # b7r6 SSH keys + groups come from the fleet user registry (users.dhall) via
  # the hyper-modern-nixos.identity module.

  # ── attic api-server replica (module self-wires its secrets) ────────────────
  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
  };

  # ── ClickHouse Keeper (coordination plane) ──────────────────────────────────
  hyper-modern-nixos.databases.clickhouse.keeper.enable = true;

  # ── OTel agent (host metrics + journald → watchtower gateway) ──────────────
  hyper-modern-nixos.observability.otel.agent = {
    enable = true;
    scrapeTargets = [
      "127.0.0.1:9153" # coredns
      "127.0.0.1:9364" # clickhouse-keeper
    ];
  };

  # ── media servers: Navidrome (music) + Jellyfin (video, NVENC) ─────────────
  # Library lives at /var/lib/media (declared authoritative by the module, so
  # it's restic-backed + impermanence-persisted via the state registry). Ports
  # are open on the LAN (enp113s0) for the Google TV and on the tailnet
  # (tailscale0 trusted fleet-wide) for phone/laptop. Jellyfin transcodes on the
  # 5090 since hyper-modern-nixos.nvidia is enabled above.
  #   - Navidrome : http://guccimane:4533  (music: /var/lib/media/music)
  #   - Jellyfin  : http://guccimane:8096  (video: /var/lib/media/video)
  hyper-modern-nixos.media = {
    enableNavidrome = true;
    enableJellyfin = true;
  };

  # ── Pinchflat: yt-dlp media manager (queue/subscribe playlists) ────────────
  # Web UI on :8945 (tailnet-only). Image pulled from the fleet zot registry;
  # downloads land in the shared /var/lib/media so the tagging pipeline +
  # Navidrome/Jellyfin pick them up. Smoke-testing SoundCloud-source handling.
  hyper-modern-nixos.pinchflat.enable = true;

  # ── R2 dropbox: shareable URLs for private files (secret-gist model) ────────
  # `drop <file>` → unguessable token dir in the straylight-drop bucket → prints
  # https://drop.sju1.s4.gl/d/<token>/<file>. Bucket not listable + autoindex off,
  # so the token is the capability. STAGED on the tailnet (CoreDNS + internal TLS)
  # for now; graduate to truly-public DNS all at once later. See
  # docs/src/architecture/dropbox.md.
  hyper-modern-nixos.dropbox = {
    enable = true;
    mountEnable = true; # bucket exists + remote resolves; mount the share
    domain = "drop.sju1.s4.gl";
  };

  # nginx fronts the dropbox mount at drop.sju1.s4.gl. CoreDNS resolves the `drop`
  # service tag (registry/hosts.dhall) → guccimane; the wildcard *.sju1.s4.gl cert
  # comes via Njalla DNS-01. Static root over the FUSE mount; autoindex off keeps
  # the bucket non-listable.
  hyper-modern-nixos.reverseProxy = {
    enable = true;
    services.drop = {
      root = "/mnt/r2/drop";
      maxBodySize = "0"; # large file fetches, no cap
    };
    services.navidrome = {
      port = 4533;
      protected = true;
    };
    services.jellyfin = {
      port = 8096;
      protected = false; # SSO plugin handles auth directly with Kanidm
    };
    services.pinchflat = {
      port = 8945;
      protected = true;
    };
  };

  # ── Jellyfin SSO plugin config (OIDC directly against Kanidm) ────────────────
  age.secrets.jellyfin-oidc-secret = {
    file = ../../../secrets/agenix/machines/kanidm-jellyfin-secret.age;
    owner = "jellyfin";
    group = "jellyfin";
    mode = "0400";
  };

  # declarative SSO plugin install + OIDC config (exact XML format from the plugin's serializer)
  systemd.services.jellyfin.preStart =
    let
      ssoPlugin = pkgs.fetchzip {
        url = "https://github.com/9p4/jellyfin-plugin-sso/releases/download/v4.0.0.4/sso-authentication_4.0.0.4.zip";
        hash = "sha256-MJTyE6CeVLk7mlugauJ/F6bpi1kYwNtzNmQeH3+CFeQ=";
        stripRoot = false;
      };
    in
    ''
          # install plugin DLLs
          mkdir -p /var/lib/jellyfin/plugins/SSO
          cp -f ${ssoPlugin}/*.dll ${ssoPlugin}/meta.json /var/lib/jellyfin/plugins/SSO/
          chmod -R u+w /var/lib/jellyfin/plugins/SSO

          # write OIDC config (only if not already configured — don't clobber user edits)
          CONF=/var/lib/jellyfin/plugins/configurations/SSO-Auth.xml
          if ! grep -q "kanidm" "$CONF" 2>/dev/null; then
            mkdir -p /var/lib/jellyfin/plugins/configurations
            SECRET=$(cat /run/agenix/jellyfin-oidc-secret)
            cat > "$CONF" << XMLEOF
      <?xml version="1.0" encoding="utf-8"?>
      <PluginConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        <SamlConfigs />
        <OidConfigs>
          <item>
            <key>
              <string>kanidm</string>
            </key>
            <value>
               <PluginConfiguration>
          <OidEndpoint>https://auth.s4.gl/oauth2/openid/jellyfin/.well-known/openid-configuration</OidEndpoint>
          <OidClientId>jellyfin</OidClientId>
          <OidSecret>$SECRET</OidSecret>
          <OidScopes>
            <string>email</string>
            <string>profile</string>
            <string>groups</string>
          </OidScopes>
          <RoleClaim>groups</RoleClaim>
          <Enabled>true</Enabled>
          <EnableAuthorization>true</EnableAuthorization>
          <EnableAllFolders>true</EnableAllFolders>
          <EnabledFolders />
          <AdminRoles>
            <string>fleet_admins@s4.gl</string>
          </AdminRoles>
          <Roles>
            <string>fleet_admins@s4.gl</string>
            <string>fleet_users@s4.gl</string>
            <string>forgejo_users@s4.gl</string>
          </Roles>
          <EnableFolderRoles>false</EnableFolderRoles>
          <EnableLiveTvRoles>false</EnableLiveTvRoles>
          <EnableLiveTv>false</EnableLiveTv>
          <EnableLiveTvManagement>false</EnableLiveTvManagement>
                <SchemeOverride>https</SchemeOverride>
          <PortOverride xsi:nil="true" />
                <NewPath>false</NewPath>
                <CanonicalLinks />
                <DisableHttps>false</DisableHttps>
                <DisablePushedAuthorization>false</DisablePushedAuthorization>
                <DoNotValidateEndpoints>false</DoNotValidateEndpoints>
                <DoNotValidateIssuerName>false</DoNotValidateIssuerName>
                <DoNotLoadProfile>false</DoNotLoadProfile>
              </PluginConfiguration>
            </value>
          </item>
        </OidConfigs>
      </PluginConfiguration>
      XMLEOF
          fi
    '';

  # ── oauth2-proxy (gates navidrome + pinchflat through Kanidm) ───────────────
  age.secrets.oauth2-proxy-secret.file = ../../../secrets/agenix/machines/oauth2-proxy-guccimane-secret.age;
  age.secrets.oauth2-proxy-cookie.file = ../../../secrets/agenix/machines/oauth2-proxy-guccimane-cookie.age;

  hyper-modern-nixos.oauth2-proxy = {
    enable = true;
    clientId = "guccimane-proxy";
    clientSecretFile = "/run/agenix/oauth2-proxy-secret";
    cookieSecretFile = "/run/agenix/oauth2-proxy-cookie";
  };

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────
  # Module self-wires its secrets from the names below (per-host R2 env:
  # restic-r2-env.guccimane). FIRST init is declarative + idempotent:
  #   nix run .#restic-init -- guccimane
  # then the daily timer drives it. /home only first; widen later.
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.guccimane";
    paths = [ "/home" ];
  };

  time.timeZone = "America/New_York";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # ── Per-host monitor & display config ──────────────────────────────────────
  # TODO: set monitor descriptions once displays are connected
  # home-manager.users.b7r6 = {
  #   hyper-modern-nixos = {
  #     hyprland.monitors = { };
  #     themes.display = {
  #       profile = "lg-ultragear-oled";
  #       highDPI = true;
  #       width = 3840;
  #       height = 2160;
  #     };
  #   };
  # };

  system.stateVersion = "24.05";
}
