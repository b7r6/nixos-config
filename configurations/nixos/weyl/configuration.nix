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

  networking.hosts = {
    "192.168.50.12" = [ "files01.rhosts.net" ];
    "10.215.1.12" = [ "cc1-agiti.cloud.parabolicsurf.net" ];
  };

  # TODO[b7r6]: we've got to either converge or diverge on
  # `autowire`, this in-between isn't working out...

  hyper-modern-nixos.nvidia.enable = true;

  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    xwayland.enable = false;
  };

  fonts.fontconfig = {
    enable = true;

    hinting = {
      enable = false;
      style = "slight"; # Options: none, slight, medium, full
    };

    antialias = false; # Smoothens the appearance of fonts
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
