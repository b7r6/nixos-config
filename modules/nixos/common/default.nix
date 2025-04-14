{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
in
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
    ./docker.nix
    ./vpn.nix
  ];


  # `home-manager` setup for nixos targets
  # this is potentially a top-level configuration opportunity...

  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  nixpkgs.config = {
    allowBroken = false;
    allowUnfree = true;
  };

  security.sudo.wheelNeedsPassword = false;
  programs.nh.enable = true;

  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "hm-backup";

  # Enable the network module with custom settings
  services.my-network = {
    enable = true;

    # Specify your Tailscale network domain
    tailnet.domain = "risk-nunki.ts.net";

    # Enable firewall with Tailscale-aware rules
    firewall.enable = false;

    # Optionally use backup DNS resolvers
    useBackupResolver = true;
  };
}
