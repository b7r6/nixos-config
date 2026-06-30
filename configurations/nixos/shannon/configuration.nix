{ flake, lib, ... }:
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

  # ── New Suzuki Quickshell prototype ────────────────────────────────────────
  # Runs alongside waybar/mako/wofi for now. Kill with `pkill quickshell`.
  # Set exclusive = true to disable the old shell components.
  home-manager.users.b7r6.hyper-modern-nixos.new-suzuki = {
    enable = true;
    exclusive = true;
  };

  users.users.b7r6 = {
    extraGroups = [
      "wheel"
      "docker"
    ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINbn+XF6n9v9VKLFGLBVz+G1LyL6GlcgZbIwhP89PPsp" # weyl b7r7 key
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1ptqyz5C3YCcMgh3LUbXtjeS1rIZ5/6RHnH7D93Nqf" # 1password id_ed25519_b7r6
    ];
  };

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
  system.stateVersion = "25.05"; # Did you read the comment?
}
