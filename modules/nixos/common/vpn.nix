{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.my-network;
in
{
  options.services.my-network = {
    enable = mkEnableOption "My network configuration with Tailscale and Mullvad";

    tailnet = {
      domain = mkOption {
        type = types.str;
        default = "example.ts.net";
        description = "Your Tailscale network domain";
      };
    };

    firewall = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable the firewall with Tailscale-aware rules";
      };
    };

    useBackupResolver = mkOption {
      type = types.bool;
      default = false;
      description = "Use backup DNS resolvers in addition to Tailscale DNS";
    };
  };

  config = mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "client"; # Accept routes from Tailscale network
      extraUpFlags = [
        "--accept-routes" # Accept subnet routes
        "--accept-dns=true" # Accept DNS settings from Tailscale
        "--ssh" # Enable Tailscale SSH
      ];
    };

    # Enable Mullvad VPN
    services.mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };

    # Firewall configuration
    networking.firewall = {
      enable = cfg.firewall.enable;

      trustedInterfaces = mkIf cfg.firewall.enable [ "tailscale0" ];
      allowedTCPPorts = mkIf cfg.firewall.enable [ 22 3000 ];
      allowedUDPPorts = mkIf cfg.firewall.enable [ 41641 ];
      checkReversePath = mkIf cfg.firewall.enable "loose";

      interfaces = mkIf cfg.firewall.enable {
        tailscale0.allowAll = true;
      };
    };

    networking = {
      nameservers =
        if cfg.useBackupResolver
        then [ "100.100.100.100" "1.1.1.1" "8.8.8.8" ]
        else [ "100.100.100.100" ];

      search = [ cfg.tailnet.domain ];
      networkmanager.dns = "none"; # Let the OS handle DNS configuration
    };

    services.openssh = {
      enable = true;
    };

    environment.systemPackages = with pkgs; [
      curl
      dig
      inetutils
      mullvad-vpn
      nmap
      tailscale
      traceroute
    ];
  };
}
