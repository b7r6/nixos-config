{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.hypermodern.libvirt;
in
{
  options.hypermodern.libvirt = {
    enable = mkEnableOption "hypermodern.libvirt" // {
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
