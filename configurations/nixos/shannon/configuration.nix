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

  # disable wifi BSS roaming — MT7925 driver panics during AP transitions.
  # the chip keeps trying to roam between 2.4/5GHz APs on the same SSID every
  # ~5min, and eventually one transition causes a kernel panic. pinning to a
  # single BSSID or disabling background scanning prevents this.
  networking.networkmanager.wifi = {
    scanRandMacAddress = false; # some firmwares crash on randomized scans
    backend = "wpa_supplicant";
  };
  # disable wpa_supplicant background scanning (prevents roaming)
  environment.etc."NetworkManager/conf.d/no-roam.conf".text = ''
    [connection-wifi]
    wifi.bgscan=
  '';

  networking.hosts = { };

  hyper-modern-nixos.nvidia.enable = true;

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

  # Wayland/Hyprland via the consolidated common module (nixpkgs hyprland).
  # Previously this host pinned a now-removed `inputs.hyprland`; the fleet
  # standard is the hyper-wayland module.
  hyper-modern-nixos.hyper-wayland.enable = true;

  # shannon prefers crisp pixel fonts: override the hyper-wayland defaults
  # (which enable antialias/hinting) with mkForce.
  fonts.fontconfig = {
    enable = true;

    hinting = {
      enable = lib.mkForce false;
      style = "slight"; # Options: none, slight, medium, full
    };

    antialias = lib.mkForce false; # Smoothens the appearance of fonts
  };

  environment.variables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  programs.firefox.enable = true;

  users.groups."ps-v4" = { };

  users.users.b7r6 = {
    extraGroups = [
      "wheel"
      "docker"
      "ps-v4"
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
