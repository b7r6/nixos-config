{
  flake,
  config,
  pkgs,
  ...
}:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
    inputs.ps-v4.nixosModules.secrets
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "weyl";
  networking.networkmanager.enable = true;

  networking.hosts = {
    "192.168.50.12" = [ "files01.rhosts.net" ];
  };

  # TODO[b7r6]: we've got to either converge or diverge on
  # `autowire`, this in-between isn't working out...
  #
  hyper-modern-nixos.nvidia.enable = true;

  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
    xwayland.enable = false;
  };

  environment.variables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  programs.firefox.enable = true;

  users.groups."ps-v4" = { };

  users.users.gedanziger = {
    isNormalUser = true;

    extraGroups = [
      "wheel"
      "ps-v4"
    ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEU8Z7JibxxeULoRcIhTS2uaKfr6SWRMJJCWpldFRnZ2 grandpa-mac"
    ];
  };

  users.groups.ps-v4 = { };
  users.users.b7r6 = {
    extraGroups = [ "ps-v4" ];
  };

  security.sudo.wheelNeedsPassword = false;

  ps-v4.nixos.secrets.devKeys = true;
  age.secrets."keys/dev.toml" = {
    # TODO[b7r6]: get this sorted or just build a proper `sops.nix`
    # setup now that we understand how and why...
    # file = ps-v4.nixos.secrets.keys.dev.file;

    file = "${inputs.ps-v4}/secrets/keys/dev.toml.age";
    group = "ps-v4";
    mode = "440";
  };

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
