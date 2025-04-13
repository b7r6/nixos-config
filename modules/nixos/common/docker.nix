{ config, pkgs, ... }:
{
  # Enable Docker properly
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    autoPrune.enable = true;
  };

  # Make sure Podman's Docker compatibility is disabled
  virtualisation.podman = {
    enable = false;  # Set to false if you don't need Podman
    dockerCompat = false;  # Disable Docker compatibility mode
  };

  # Add your user to the "docker" group
  users.users.b7r6.extraGroups = [ "docker" ];
}
