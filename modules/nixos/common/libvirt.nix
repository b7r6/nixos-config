{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.hypermodern.nixos.libvirt;
in
{
  options.hypermodern.nixos.libvirt = {
    enable = mkEnableOption "hypermodern.nixos.libvirt" // {
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
