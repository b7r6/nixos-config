{
  flake,
  lib,
  pkgs,
  ...
}:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "shannon";
  networking.networkmanager.enable = true;

  # ═══════════════════════════════════════════════════════════════════════════
  # TODO[b7r6]: SERVER ROLES DISABLED for the LUKS reinstall (2026-10-08).
  #
  # The 2026-10-07 fleet sell-off consolidated the whole server stack onto this
  # laptop (attic, nativelink + nix-cache, clickhouse, coredns, otel agent +
  # gateway, grafana, nginx/acme). Those roles drag heavy from-source fork/
  # Haskell/Rust builds (nativelink=Rust, coredns-zone/hnix/dhall=Haskell,
  # clickhouse=C++) that exist on NO public binary cache — the only cache that
  # ever held them was this box's own loopback nativelink nix_cache, which does
  # not exist during `disko-install`. That is why a clean install compiles for
  # hours. None of it is needed for a bootable encrypted DESKTOP.
  #
  # To restore the server stack after the box is reinstalled and can rebuild/
  # serve its own cache again: delete the `/* … */` wrappers below AND the two
  # `mkForce false` lines that follow the block.
  # ═══════════════════════════════════════════════════════════════════════════
  /*
  # ── attic api-server replica (module self-wires its secrets) ────────────────

  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
  };

  # ── OTel agent (host metrics + journald → watchtower gateway) ──────────────

  hyper-modern-nixos.observability.otel.agent = {
    enable = true;

    scrapeTargets = [
      "127.0.0.1:9153" # coredns
      "127.0.0.1:9363" # clickhouse
      "127.0.0.1:9364" # clickhouse-keeper
    ];
  };

  # ── NativeLink: the whole fleet in one laptop (scheduler + CAS + worker) ────
  # Fleet sell-off 2026-10-07: shannon inherits the scheduler role and is the
  # only shard in the CAS ring (weight 1, 16G fast tier — disk-constrained).
  # R2 remains the slow tier, so cache contents outlive this disk.
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;

  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = "shannon";
    openFirewall = true;

    r2 = {
      enable = true;
      accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
      bucket = "straylight-nativelink-cas";
      environmentFile = "/run/agenix/nativelink-r2-env";
    };
  };

  # ── OTel gateway: the observability spine lands on the laptop ──────────────
  # The registry `ch` tag moved here with the fleet sell-off, so this node is
  # both agent and gateway; the module fuses them into one collector writing
  # straight into the local ClickHouse (otel database).
  hyper-modern-nixos.observability.otel.gateway.enable = true;

  # ── Grafana: single-box flavor of watchtower's stack ───────────────────────
  # Localhost only (no nginx edge, no kanidm OAuth — the IdP retired with
  # watchtower). ClickHouse datasource + the same Dhall-rendered dashboards.
  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3300;
        root_url = "https://grafana.sju1.s4.gl/";
        domain = "grafana.sju1.s4.gl";
      };

      security = {
        admin_user = "admin";
        admin_password = "$__file{/run/agenix/grafana-admin-password}";
        secret_key = "$__file{/run/agenix/grafana-admin-password}";
      };

      "auth.anonymous".enabled = false;
    };

    declarativePlugins = [ pkgs.grafanaPlugins.grafana-clickhouse-datasource ];

    provision = {
      enable = true;

      datasources.settings.datasources = [
        {
          name = "ClickHouse";
          type = "grafana-clickhouse-datasource";
          uid = "clickhouse";
          access = "proxy";
          isDefault = true;
          jsonData = {
            host = "127.0.0.1";
            port = 9000;
            protocol = "native";
            defaultDatabase = "otel";
            username = "default";
          };
        }
      ];

      dashboards.settings.providers = [
        {
          name = "fleet";
          type = "file";
          options.path = "/etc/grafana/dashboards";
          options.foldersFromFilesStructure = true;
        }
      ];
    };
  };

  # render dashboards from Dhall → JSON (same apparatus as watchtower ran)
  environment.etc =
    let
      grafanaDir = ../../../modules/flake/grafana;
      dashboardDir = "${grafanaDir}/dashboards";
      dhallFiles = builtins.filter (n: builtins.match ".*\\.dhall" n != null) (
        builtins.attrNames (builtins.readDir dashboardDir)
      );
      renderDashboard =
        file:
        let
          name = builtins.replaceStrings [ ".dhall" ] [ "" ] file;
        in
        pkgs.runCommand "grafana-dashboard-${name}.json" { nativeBuildInputs = [ pkgs.dhall-json ]; } ''
          export HOME="$TMPDIR"
          export XDG_CACHE_HOME="$TMPDIR/dhall-cache"
          mkdir -p "$XDG_CACHE_HOME"
          dhall-to-json --file ${grafanaDir}/dashboards/${file} > $out
        '';
    in
    builtins.listToAttrs (
      map (
        file:
        let
          name = builtins.replaceStrings [ ".dhall" ] [ "" ] file;
        in
        {
          name = "grafana/dashboards/${name}.json";
          value.source = renderDashboard file;
        }
      ) dhallFiles
    );

  age.secrets.grafana-admin-password = {
    file = ../../../secrets/agenix/machines/grafana-admin-password.age;
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  # ── nginx vhosts: TLS names for the single-box stack ───────────────────────
  # Split-horizon: coredns resolves <sub>.sju1.s4.gl here (grafana/ch tags),
  # nginx terminates the wildcard LE cert and proxies to loopback. No
  # `protected` vhosts — oauth2-proxy's IdP retired with watchtower.
  hyper-modern-nixos.reverseProxy = {
    enable = true;

    services.grafana.port = 3300;
    services.ch.port = 8123; # clickhouse HTTP interface
  };

  # ── ClickHouse: single-node keeper + server, S3→R2 durable tier ─────────────
  # Keeper membership is registry-derived (shannon is the only host tagged
  # `clickhouse-keeper` after the sell-off → 1-node ensemble). The server's
  # local disk is reconstructible cache; R2 is the durable truth.
  hyper-modern-nixos.databases.clickhouse = {
    keeper = {
      enable = true;
      # One box IS the fleet now; durability is the S3→R2 tier, not quorum.
      allowSolo = true;
    };
    server = {
      enable = true;
      s3.enable = true;
    };
  };

  # ── CoreDNS as this node's own resolver (serves s4.gl — git, auth, grafana) ─
  # Last fleet holdout: without it, flake inputs from git.s4.gl can't resolve
  # off-tailnet-DNS and the attic replica can't look up watchtower.
  hyper-modern-nixos.coredns.enable = true;

  # ── nativelink nix-cache: bounded fast tier over R2 ────────────────────────
  # Re-enabled (fleet default) after the 2026-10-07 disk incident, but with the
  # local fast tier capped: with r2.enable the NAR store is fastSlow(local, R2
  # nix-nar/), so eviction from the 32G local tier never loses data — R2 is the
  # durable copy. The uncapped default grew to 201G on this ~1T laptop.
  hyper-modern-nixos.nativelink.nixCache = {
    fastCacheBytes = 34359738368; # 32 GiB

    # Read-through: a miss here consults upstream and mirrors the NAR into the
    # local CAS (→ R2) instead of just 404ing the client into fallthrough.
    # Same pair guccimane ran.
    upstreamCaches = [
      {
        url = "https://cache.nixos.org";
        trustedPublicKeys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
      }
      {
        url = "https://nix-community.cachix.org";
        trustedPublicKeys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
      }
    ];
  };
  */

  # TODO[b7r6]: neutralize the fleet-wide defaults (modules/nixos/default.nix)
  # that would otherwise re-enable the nativelink nix-cache (and its Rust build)
  # on every host. Drop these two lines when re-enabling the server block above.
  hyper-modern-nixos.nativelink.enable = lib.mkForce false;
  hyper-modern-nixos.nativelink.nixCache.enable = lib.mkForce false;

  # ── Tailscale safety net ────────────────────────────────────────────────────

  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
  hyper-modern-nixos.network.tailscale.exitNodeRotation.enable = true;

  # ── Secureframe device agent (fleet-orbit / osquery) ───────────────────────
  # Reproduces Secureframe's personalized agent .deb declaratively: the ORBIT_*
  # env (fleet URL + enroll secret + channels) extracted from /etc/default/orbit
  # → agenix; the --specified_identifier triple from the .deb's orbit.service
  # links this box to its Secureframe device record. Re-extract from a fresh
  # .deb to rotate (see modules/nixos/fleet-orbit.nix).
  age.secrets.fleet-orbit-env.file = ../../../secrets/agenix/machines/fleet-orbit-env.age;
  hyper-modern-nixos.fleet-orbit = {
    enable = true;
    environmentFile = "/run/agenix/fleet-orbit-env";
    hostIdentifier = "edaca163-3f94-4cbc-85c0-b48d42706d20:aec2d51b-d62c-4bce-807e-369335e0f71e:17a29c92-b56c-48ab-977e-7d5d678bb93c";
  };

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────

  # Per-host repo (backups-restic/shannon). FIRST init:  nix run .#restic-init -- shannon
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.shannon";
    paths = [ "/home" ];
  };

  # ── laptop backpressure: swap-backed memory pressure + early OOM relief ────
  # zram gives systemd-oomd a pressure signal to act on; without swap it goes
  # straight from "fine" to kernel OOM/lockup under big parallel builds.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  systemd.oomd = {
    enableRootSlice = true;
    enableUserSlices = true;
    extraConfig.DefaultMemoryPressureDurationSec = "20s";
  };

  # /bin/bash etc. for FHS-assuming tools (Bazel genrules, scripts).
  services.envfs.enable = true;

  # TODO[b7r6]: aarch64 emulation was for cross-evaluating the (now-sold) fleet's
  # native-aarch64 registry IFDs. Dead weight for a standalone laptop; re-enable
  # if this box ever needs to `nix flake check` aarch64 hosts again.
  # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  environment.variables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  programs.firefox.enable = true;

  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "America/New_York";
  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # ── Wayland/Hyprland ────────────────────────────────────────────────────────
  hyper-modern-nixos.wayland.enable = true;

  # Battery reporting for the new-suzuki shell (BatteryService reads UPower)
  services.upower.enable = true;

  # ── Per-host monitor & display config ──────────────────────────────────────
  home-manager.users.b7r6 = {
    hyper-modern-nixos = {
      hyprland.monitors = (import ../../../lib/monitors.nix).shannon;

      themes.display = {
        # Samsung OLED internal panel at scale 2.0 → 192dpi logical
        profile = "oled";
        highDPI = true;
        width = 2880;
        height = 1800;
      };

      # ── The rice ─────────────────────────────────────────────────────────
      # Same shell as gossamer/shimmer: new-suzuki + wintermute, exclusive
      # mode replaces waybar/wofi/mako and takes the keybinds. No cudaField —
      # the panel is driven by the AMD iGPU, the QML wallpaper does the work.
      new-suzuki = {
        enable = true;
        exclusive = true;
      };
    };
  };

  system.stateVersion = "25.05"; # Did you read the comment?
}
