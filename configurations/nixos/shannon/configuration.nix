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

  networking.hostName = "shannon";
  networking.networkmanager.enable = true;

  # ── attic api-server replica (module self-wires its secrets) ────────────────

  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
  };

  # ── OTel agent (host metrics + journald → watchtower gateway) ──────────────

  hyper-modern-nixos.observability.otel.agent.enable = true;

  # ── Tailscale safety net ────────────────────────────────────────────────────

  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # CoreDNS as this node's own resolver (serves s4.gl — git, auth, grafana, …)
  hyper-modern-nixos.coredns.enable = true;

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────

  # Per-host repo (backups-restic/shannon). FIRST init:  nix run .#restic-init -- shannon
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.shannon";
    paths = [ "/home" ];
  };

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

  hyper-modern-nixos.new-suzuki = {
    enable = true;
    battery.enable = true;
  };

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

    };
  };

  system.stateVersion = "25.05"; # Did you read the comment?
}
