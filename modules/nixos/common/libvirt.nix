{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.libvirt;
in
{
  options.hyper-modern-nixos.libvirt = {
    enable = mkEnableOption "hyper-modern-nixos.libvirt" // {
      default = true;
    };
  };

  config = mkIf cfg.enable {
    virtualisation.libvirtd.enable = true;
    environment.systemPackages = with pkgs; [
      virt-manager
      virt-viewer
      spice-gtk
      OVMF
      qemu
    ];
  };
}
