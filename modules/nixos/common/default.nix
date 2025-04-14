{ flake, pkgs, ... }:
{
  imports = [
    ./cachix.nix
    ./bluetooth.nix
    ./libvirt.nix
    ./myusers.nix
    ./network-manager.nix
    ./nix-ld.nix
    ./secrets.nix
    ./ssh.nix
    ./usb.nix
    ./vpn.nix
  ];

  # `home-manager` setup for nixos targets
  # this is potentially a top-level configuration opportunity...

  nix.nixPath = [ "nixpkgs=${flake.inputs.nixpkgs}" ];
  nixpkgs.config = {
    allowBroken = false;
    allowUnfree = true;
  };

  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "dev-v4-hm-backup";
}
