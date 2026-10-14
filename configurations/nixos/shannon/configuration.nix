{
  flake,
  lib,
  options,
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
  # Restoring it one role at a time (2026-10-12): each role moves OUT of the
  # `/* … */` block below into the live config once it builds and verifies.
  # Back so far: nativelink nix-cache, NativeLink RE (scheduler+CAS+worker),
  # ClickHouse (keeper + server), OTel agent + gateway, Grafana.
  # ═══════════════════════════════════════════════════════════════════════════
  /*
    # ── attic api-server replica (module self-wires its secrets) ────────────────

    hyper-modern-nixos.attic-node = {
      enable = true;
      profile = "replica";
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

    # ── CoreDNS as this node's own resolver (serves s4.gl — git, auth, grafana) ─
    # Last fleet holdout: without it, flake inputs from git.s4.gl can't resolve
    # off-tailnet-DNS and the attic replica can't look up watchtower.
    hyper-modern-nixos.coredns.enable = true;
    hyper-modern-nixos.observability.otel.agent.scrapeTargets = [ "127.0.0.1:9153" ]; # coredns
  */

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

  # ── OTel agent (host metrics + journald → local gateway) ──────────────

  hyper-modern-nixos.observability.otel.agent = {
    enable = true;

    # coredns (:9153) rejoins this list with its role (disabled block above);
    # scraping it while parked is a down target and a warn every 30s.
    scrapeTargets = [
      "127.0.0.1:9363" # clickhouse
      "127.0.0.1:9364" # clickhouse-keeper
    ];
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

  # render dashboards from Dhall → JSON (same apparatus as watchtower ran).
  # One level of subfolders is honoured: dashboards/retired/*.dhall lands in
  # /etc/grafana/dashboards/retired/, which foldersFromFilesStructure turns
  # into a "retired" Grafana folder — the top level stays dashboards with data.
  environment.etc =
    let
      grafanaDir = ../../../modules/flake/grafana;
      dashboardDir = "${grafanaDir}/dashboards";
      isDhall = n: builtins.match ".*\\.dhall" n != null;
      # relative paths ("fleet-overview.dhall", "retired/attic.dhall")
      dhallFiles =
        let
          top = builtins.readDir dashboardDir;
          files = builtins.filter isDhall (builtins.attrNames top);
          dirs = builtins.filter (n: top.${n} == "directory") (builtins.attrNames top);
          sub = builtins.concatMap (
            d:
            map (f: "${d}/${f}") (
              builtins.filter isDhall (builtins.attrNames (builtins.readDir "${dashboardDir}/${d}"))
            )
          ) dirs;
        in
        files ++ sub;
      renderDashboard =
        file:
        let
          name = builtins.replaceStrings [ ".dhall" "/" ] [ "" "-" ] file;
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

  # ── nativelink nix-cache: ON (fleet default), standalone ──────────────────
  # The substituter + nl-watch-store. The cache needs nativelink.r2 for its
  # fast_slow NAR store but NOT nativelink.enable (the RE server, below).
  # The bootstrap profile turns all of this off, so a clean install still
  # builds from public caches.
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;

  hyper-modern-nixos.nativelink.r2 = {
    enable = true;
    accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
    bucket = "straylight-nativelink-cas";
    environmentFile = "/run/agenix/nativelink-r2-env";
  };

  # Bounded fast tier over R2. Re-enabled (fleet default) after the 2026-10-07 disk incident, but with the
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

  # ── NativeLink: the whole fleet in one laptop (scheduler + CAS + worker) ────
  # Fleet sell-off 2026-10-07: shannon inherits the scheduler role and is the
  # only shard in the CAS ring (weight 1, 16G fast tier — disk-constrained).
  # R2 remains the slow tier, so cache contents outlive this disk.
  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = "shannon";
    openFirewall = true;
  };

  # The rendered config dials its own scheduler/CAS as shannon.sju1.s4.gl —
  # a name only CoreDNS/MagicDNS ever answered. One box IS the fleet, so pin
  # it to loopback: RE comes up on any network, with or without either.
  networking.hosts."127.0.0.1" = [ "shannon.sju1.s4.gl" ];

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

  # HOLD (2026-10 LUKS reinstall): no backups until the rebuilt /home is set up
  # the way we want it. Every backup run is followed by `restic forget`, and
  # the default retention would age out the last pre-reinstall snapshot
  # (98947d3f, 2026-10-09) within ~7 days — that snapshot is what selective
  # restores come from. Remove this line to resume hourly backups.
  systemd.timers.restic-backups-system.enable = lib.mkForce false;

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
    settings.OOM.DefaultMemoryPressureDurationSec = "20s";
  };

  # /bin/bash etc. for FHS-assuming tools (Bazel genrules, scripts).
  services.envfs.enable = true;

  # ── Bounded builds: this is a 13" chassis ──────────────────────────────────
  # 24 threads × unlimited cores × no swap is how the 2026-10 reinstalls hung
  # silently (RAM, then thermals — see the governor note in
  # hardware-configuration.nix). 4 jobs × 8 cores keeps peak RSS and package
  # power inside what the box can sustain; raise per-invocation with
  # `--max-jobs/--cores` when docked and watching it.
  nix.settings = {
    max-jobs = lib.mkDefault 4;
    cores = lib.mkDefault 8;
  };

  # TODO[b7r6]: aarch64 emulation was for cross-evaluating the (now-sold) fleet's
  # native-aarch64 registry IFDs. Dead weight for a standalone laptop; re-enable
  # if this box ever needs to `nix flake check` aarch64 hosts again.
  # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # ── GPU: amdgpu drives the panel, the RTX (AD107) is a PRIME offload card ──
  # Proprietary `latest` driver via hyper-modern-nixos.nvidia (CUDA wallpapers).
  # The eDP panel hangs off the iGPU; the dGPU only owns HDMI-A-1. Neither PCI
  # function carries boot_vga=1 on this ASUS, so whichever KMS driver registers
  # first becomes card1 — and weston (the SDDM greeter) opens that one. On
  # 2026-10-11 nouveau won the race, weston got a card with no atomic KMS and
  # died, leaving no greeter. amdgpu in the initrd makes the iGPU card1, always.
  hyper-modern-nixos.nvidia.enable = true;
  hardware.amdgpu.initrd.enable = true;

  # The kernel-rendered EYES still behind the greeter (and the lock screen,
  # below), matching the live CUDA wallpaper. Rendered on the CPU at build time.
  hyper-modern-nixos.greeter.eyesStill = true;

  # The greeter's weston opens ONE DRM device: the lowest cardN. Card numbers
  # are first-come — simpledrm holds minor 0 at boot, amdgpu takes minor 1 and
  # frees 0 when it replaces simpledrm, then nvidia-drm grabs 0 — so weston
  # landed on the dGPU (only HDMI-A-1, disconnected), found no outputs, exited,
  # and left a bare console. Resolve the iGPU by PCI path at launch instead.
  # (Hyprland opens every GPU, which is why the session itself was always fine.)
  services.displayManager.sddm.wayland.compositorCommand =
    let
      upstream = options.services.displayManager.sddm.wayland.compositorCommand.default;
      onIgpu = pkgs.writeShellScript "sddm-weston-igpu" ''
        card=$(${pkgs.coreutils}/bin/readlink -f /dev/dri/by-path/pci-0000:c5:00.0-card)
        exec ${upstream} ''${card:+--drm-device=''${card##*/}} "$@"
      '';
    in
    "${onIgpu}";

  hardware.nvidia = {
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true; # `nvidia-offload <cmd>`
      amdgpuBusId = "PCI:197@0:0:0"; # c5:00.0
      nvidiaBusId = "PCI:196@0:0:0"; # c4:00.0
    };
    # Laptop: let the dGPU power down (RTD3) when idle, and save VRAM across
    # suspend (mem_sleep_default=deep). The fleet module defaults both off.
    powerManagement.enable = lib.mkForce true;
    powerManagement.finegrained = lib.mkForce true;
  };

  # No global __GLX_VENDOR_LIBRARY_NAME=nvidia: under PRIME offload it would put
  # every GL client on the dGPU and pin it awake. `nvidia-offload` sets it per
  # process.
  environment.variables = {
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
    # Opt-in RBE against this box's own NativeLink (scheduler :50051, instance
    # `main`): `bazel build --config=rbe-local //...`. Named, not default, so
    # other workspaces keep their own remote settings. --jobs matches the
    # worker's max_inflight_tasks (fleet.dhall).
    home.file.".bazelrc".text = ''
      build:rbe-local --remote_executor=grpc://127.0.0.1:50051
      build:rbe-local --remote_instance_name=main
      build:rbe-local --remote_timeout=3600
      build:rbe-local --jobs=12
    '';

    hyper-modern-nixos = {
      hyprland.monitors = (import ../../../lib/monitors.nix).shannon;

      # TODO[b7r6]: aider + opencode disabled for the modern-nixpkgs migration —
      # on nixos-unstable @ e7439b6b they fail to build (aider's python anyio
      # test, opencode's vendored node_modules hash drift). claude-code stays
      # (nixpkgs ships it). Re-enable once upstream settles / the hash is re-pinned.
      llm.aider.enable = false;
      llm.opencode.enable = false;

      themes.display = {
        # Samsung OLED internal panel at scale 2.0 → 192dpi logical
        profile = "oled";
        highDPI = true;
        width = 2880;
        height = 1800;
      };

      lockscreen.eyesStill = true;

      # ── The rice ─────────────────────────────────────────────────────────
      # Same shell as gossamer/shimmer: new-suzuki + wintermute, exclusive
      # mode replaces waybar/wofi/mako and takes the keybinds. The wallpaper
      # is the CUDA kernel on the RTX (PRIME: rendered on the dGPU, presented
      # through wl_shm to the iGPU-driven panel — not zero-copy like GB10).
      new-suzuki = {
        enable = true;
        exclusive = true;
        cudaField = {
          enable = true;
          arch = "sm_89"; # AD107 (Ada); the x86 SDK default is sm_120
          scene = "eyes";
        };
      };
    };
  };

  system.stateVersion = "26.11"; # fresh 2026-10 LUKS reinstall — yes, read.
}
