{ config, pkgs, ... }:

let
  # Flag to enable backup resolver (set to true when needed)
  useBackupResolver = false;
in
{
  # Enable Tailscale with full routing features
  services.tailscale = {
    enable = true;

    useRoutingFeatures = "client"; # Accept routes from Tailscale network

    extraUpFlags = [
      "--accept-routes"  # Accept subnet routes
      "--accept-dns=true" # Accept DNS settings from Tailscale
      "--ssh" # Enable Tailscale SSH
    ];
  };

  # Enable Mullvad VPN
  services.mullvad-vpn = {
    enable = true;
    package = pkgs.mullvad-vpn;
  };

  # Disable firewall
  networking.firewall = {
    enable = false;
  };

  networking = {
    # Conditional DNS configuration based on flag
    nameservers = if useBackupResolver 
                 then [ "100.100.100.100" "1.1.1.1" "8.8.8.8" ] # Tailscale + backup resolvers
                 else [ "100.100.100.100" ]; # Only Tailscale DNS
    
    search = [ "risk-nunki.ts.net" ]; # Replace with your tailnet domain
    
    # Configure DNS lookups
    networkmanager.dns = "none"; # Let the OS handle DNS configuration
  };

  # Enable SSH service
  services.openssh = {
    enable = true;
  };

  # Install both packages
  environment.systemPackages = with pkgs; [
    tailscale
    mullvad-vpn
  ];

  # Keep more generations for easier rollback
  boot.loader.systemd-boot.configurationLimit = 10;
}
