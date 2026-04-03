{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  # Disable system-level emacs service (emacs is managed by home-manager)
  services.emacs.enable = false;

  # fileSystems are defined in hardware-configuration.nix

  hyper-modern-nixos.hyper-wayland = {
    enable = true;
  };

  hyper-modern-nixos.nvidia = {
    enable = true;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # boot.kernelPackages is defined in hardware-configuration.nix

  networking.hostName = "ultraviolence";
  networking.networkmanager.enable = true;

  # hardware.bluetooth is defined in hardware-configuration.nix

  services.thermald.enable = true;

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

  system.stateVersion = "25.05";
}
