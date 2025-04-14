{ config, pkgs, lib, ... }:

let
  isoConfig = import /home/b7r6/nixos-config/proart-p16/modules/system/iso.nix {
    inherit config pkgs lib;
  };
in
{
  imports = [ isoConfig ];
  
  # Disable ZFS modules
  boot.supportedFilesystems = lib.mkForce [ "btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs" ];
  boot.zfs.enabled = false;
}
