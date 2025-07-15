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

  # TODO[b7r6]: move to modules/nixos/network/
  networking.networkmanager.enable = true;

  # TODO[b7r6]: we've got to either converge or diverge on
  # `autowire`, this in-between isn't working out...

  hypermodern.nixos.nvidia.enable = true;
  hypermodern.nixos.wayland.enable = true;

  # TODO[b7r6]: move to `modules/nixos/fonts/`
  fonts.fontconfig = {
    enable = true;
    hinting = {
      enable = false;
      style = "slight";
    };
    antialias = false;
  };

  # TODO[b7r6]: move to `modules/nixos/nvidia/`
  environment.variables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  # TODO[b7r6]: once everything else is done, figure out users...
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

  # TODO[b7r6]: move to `modules/nixos/security/`
  security.sudo.wheelNeedsPassword = false;

  # TODO[b7r6]: move to `modules/nixos/locale/`
  time.timeZone = "America/New_York";
  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  # TODO[b7r6]: move to `modules/nixos/audio/`
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  system.stateVersion = "25.05";
}
