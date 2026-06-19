{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.network;
in
{
  options.hyper-modern-nixos.network = {
    enable = mkEnableOption "hyper-modern-nixos.network" // {
      default = true;
    };

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
    services.openssh = {
      enable = true;
    };

    services.tailscale = {
      enable = true;
      useRoutingFeatures = "client";
      extraUpFlags = [
        "--accept-routes" # Accept subnet routes
        "--accept-dns=true" # Accept DNS settings from Tailscale
      ];
    };

    services.mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };

    networking.firewall = {
      inherit (cfg.firewall) enable;

      trustedInterfaces = mkIf cfg.firewall.enable [ "tailscale0" ];
      allowedTCPPorts = mkIf cfg.firewall.enable [
        22
        3000
      ];

      allowedUDPPorts = mkIf cfg.firewall.enable [ 41641 ];
      checkReversePath = mkIf cfg.firewall.enable "loose";

      interfaces = mkIf cfg.firewall.enable { tailscale0.allowAll = true; };
    };

    networking = {
      # TODO[b7r6]: we need to do something here, but this isn't it...
      # nameservers =
      #   if cfg.useBackupResolver then
      #     [
      #       "100.100.100.100"
      #       "1.1.1.1"
      #       "8.8.8.8"
      #     ]
      #   else
      #     [ "100.100.100.100" ];

      # search = [ cfg.tailnet.domain ];
      # networkmanager.dns = "none";
    };

    environment.systemPackages = with pkgs; [
      wget
      ethtool
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
