{ config, pkgs, ... }:
{
  # Enable virtualization
  virtualisation.libvirtd.enable = true;

  # Install required packages
  environment.systemPackages = with pkgs; [
    virt-manager
    virt-viewer
    spice-gtk
    OVMF
    qemu
  ];
  # Add your user to libvirtd group
  users.users.b7r6.extraGroups = [ "libvirtd" ];
}
