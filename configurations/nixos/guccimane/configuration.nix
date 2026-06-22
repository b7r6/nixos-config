{ flake, ... }:
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

  # ── ClickHouse Keeper (coordination plane, member of the 3-node ensemble) ────
  # Server-less Keeper node; ensemble derived from the `clickhouse-keeper`
  # registry tag (ultraviolence/guccimane/shimmer). The ClickHouse server itself
  # lives on watchtower. See docs/infrastructure/clickhouse.md.
  hyper-modern-nixos.databases.clickhouse.keeper.enable = true;

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

  # b7r6 SSH keys + groups come from the fleet-wide hyper-modern-nixos.users
  # model (modules/nixos/default.nix + myusers.nix).

  # ── attic api-server replica (module self-wires its secrets) ────────────────
  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
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
