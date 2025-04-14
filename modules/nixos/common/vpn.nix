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
    # Enable Tailscale with full routing features
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

      # When firewall is enabled, these rules ensure Tailscale works
      trustedInterfaces = mkIf cfg.firewall.enable [ "tailscale0" ];
      allowedTCPPorts = mkIf cfg.firewall.enable [ 22 3000 ];
      allowedUDPPorts = mkIf cfg.firewall.enable [ 41641 ];
      checkReversePath = mkIf cfg.firewall.enable "loose";

      # Allow all traffic on Tailscale interface
      interfaces = mkIf cfg.firewall.enable {
        tailscale0.allowAll = true;
      };
    };

    # DNS Configuration
    networking = {
      nameservers =
        if cfg.useBackupResolver
        then [ "100.100.100.100" "1.1.1.1" "8.8.8.8" ]
        else [ "100.100.100.100" ];

      search = [ cfg.tailnet.domain ];
      networkmanager.dns = "none"; # Let the OS handle DNS configuration
    };

    # Enable SSH service
    services.openssh = {
      enable = true;
    };

    # Network emergency tools
    environment.systemPackages = with pkgs; [
      tailscale
      mullvad-vpn

      # Emergency firewall toggle scripts
      (writeScriptBin "firewall-off" ''
        #!${bash}/bin/bash
        echo "Disabling firewall..."
        ${systemd}/bin/systemctl stop firewall
        ${iptables}/bin/iptables -F
        ${iptables}/bin/iptables -X
        ${iptables}/bin/iptables -P INPUT ACCEPT
        ${iptables}/bin/iptables -P FORWARD ACCEPT
        ${iptables}/bin/iptables -P OUTPUT ACCEPT
        echo "Firewall disabled. Run 'firewall-on' to re-enable."
      '')

      (writeScriptBin "firewall-on" ''
        #!${bash}/bin/bash
        echo "Enabling firewall..."
        ${systemd}/bin/systemctl start firewall
        echo "Firewall enabled."
      '')

      # Emergency DNS toggle scripts
      (writeScriptBin "resolver-backup-on" ''
        #!${bash}/bin/bash
        echo "Enabling backup DNS resolvers..."
        echo "nameserver 100.100.100.100" > /etc/resolv.conf
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        echo "search ${cfg.tailnet.domain}" >> /etc/resolv.conf
        echo "options edns0" >> /etc/resolv.conf
        echo "Backup resolvers enabled."
      '')

      (writeScriptBin "resolver-tailscale-only" ''
        #!${bash}/bin/bash
        echo "Switching to Tailscale DNS only..."
        echo "nameserver 100.100.100.100" > /etc/resolv.conf
        echo "search ${cfg.tailnet.domain}" >> /etc/resolv.conf
        echo "options edns0" >> /etc/resolv.conf
        echo "Now using Tailscale DNS only."
      '')

      # Network diagnostic tools
      inetutils
      dig
      traceroute
      nmap
      curl
    ];

    # Keep more generations for easier rollback
    boot.loader.systemd-boot.configurationLimit = 10;
  };
}
