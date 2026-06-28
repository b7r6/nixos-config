{ flake, pkgs, ... }:
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

  # networking.hosts = {
  #   "192.168.50.12" = [ "files01.rhosts.net" ];
  #   "10.215.1.12" = [ "cc1-agiti.cloud.parabolicsurf.net" ];
  # };

  # TODO[b7r6]: we've got to either converge or diverge on
  # `autowire`, this in-between isn't working out...

  hyper-modern-nixos.nvidia.enable = true;
  hyper-modern-nixos.hyper-wayland.enable = true;

  # b7r6 keys + base groups come from the fleet-wide user model; this host just
  # adds its machine-specific group.
  # hyper-modern-nixos.users.users.b7r6.extraGroups = [ "ps-v4" ];

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
