{ flake, ... }:
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

  networking.hostName = "weyl";
  networking.networkmanager.enable = true;

  hyper-modern-nixos.coredns.enable = true;
  hyper-modern-nixos.nvidia.enable = true;
  hyper-modern-nixos.hyper-wayland.enable = true;

  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "America/Puerto_Rico";
  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # ── Per-host display config ────────────────────────────────────────────────

  home-manager.users.b7r6 = {
    hyper-modern-nixos = {

      hyprland.monitors = (import ../../../lib/monitors.nix).ultraviolence;

      themes.display = {
        profile = "lg-ultragear-oled";
        highDPI = true;
        width = 3840;
        height = 2160;
      };
    };
  };

  # ── attic api-server replica (module self-wires its secrets) ────────────────

  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
  };

  # ── NativeLink nix_cache substituter (standalone, R2-backed) ────────────────
  # weyl is a fleet nativelink CAS/worker node (2026-07-25): a CAS shard
  # (weight 2 / 32 GiB fast tier) + an x86_64 worker dialing watchtower's
  # scheduler over the tailnet. Its role + topology come from the typed Dhall
  # fleet (nativelink/fleet.dhall -> out/weyl.json). The nixCache substituter
  # below is a separate concern — it backs the NAR store with R2.
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;

  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = "weyl";
    openFirewall = true;

    r2 = {
      enable = true;
      accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
      bucket = "straylight-nativelink-cas";
      environmentFile = "/run/agenix/nativelink-r2-env";
    };

    # Read-through mirror of upstream store paths; the cas_witness proxy mirrors
    # raw fetchurl bytes. Matches ultraviolence/guccimane.
    nixCache = {
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
      fetchProxy.enable = true;
    };
  };

  # ── OTel agent (host metrics + journald → watchtower gateway) ──────────────

  hyper-modern-nixos.observability.otel.agent = {
    enable = true;

    scrapeTargets = [
      "127.0.0.1:9153" # coredns
    ];
  };

  # ── Tailscale safety net ────────────────────────────────────────────────────

  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────

  # Per-host repo (backups-restic/weyl). Module self-wires its secrets.
  # FIRST init declarative + idempotent:  nix run .#restic-init -- weyl
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.weyl";
    paths = [ "/home" ];
  };

  system.stateVersion = "25.05"; # Did you read the comment?
}
