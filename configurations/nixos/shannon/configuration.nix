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

  networking.hosts = { };

  hyper-modern-nixos.nvidia.enable = true;

  # ── Fleet services (BLOCKED on shannon's host key) ──────────────────────────
  # shannon's ed25519 host key is not yet in secrets/keys.nix (laptop was off),
  # so it can't decrypt ANY agenix secret. Once it boots:
  #   1. nix run .#scan-host-key -- shannon   (paste into keys.nix)
  #   2. nix run .#rekey-secrets               (so shannon can decrypt)
  #   3. create restic-r2-env.shannon.age (per-host R2 repo)
  #   4. uncomment the block below + deploy + `nix run .#restic-init -- shannon`
  #
  # hyper-modern-nixos.attic-node = { enable = true; profile = "replica"; };
  #
  # age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  # hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
  #
  # hyper-modern-nixos.backup = {
  #   enable = true;
  #   passwordSecret = "restic-password";
  #   environmentSecret = "restic-r2-env.shannon";
  #   paths = [ "/home" ];
  # };

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
