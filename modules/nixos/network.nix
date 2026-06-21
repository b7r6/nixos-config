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

    # ── Tailscale (adapted from straylight-infra's fxy.services.tailscale) ─────
    # The headline precaution: DECLARATIVE auth-key enrollment. When a host has
    # the auth-key agenix secret wired (authKeyFile set), tailscaled brings the
    # node up automatically — a rebuild/reinstall can't strand a remote box off
    # the tailnet waiting for a manual `tailscale up`. Hosts WITHOUT the secret
    # keep working exactly as before (manual enrollment), so this is non-breaking.
    tailscale = {
      authKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/agenix/tailscale-auth-key";
        description = ''
          Path to a file containing a Tailscale auth key (an agenix runtime
          path, never the store). When set, tailscaled enrolls non-interactively
          on first boot. When null, enrollment is manual (current behaviour).
        '';
      };

      acceptRoutes = mkOption {
        type = types.bool;
        default = true;
        description = "Accept subnet routes advertised by other nodes.";
      };

      acceptDNS = mkOption {
        type = types.bool;
        default = true;
        description = "Accept MagicDNS / tailnet DNS settings.";
      };

      advertiseRoutes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "10.0.0.0/24" ];
        description = "Subnets this node advertises as a subnet router.";
      };

      advertiseExitNode = mkOption {
        type = types.bool;
        default = false;
        description = "Advertise this node as an exit node.";
      };

      acceptExitNode = mkOption {
        type = types.bool;
        default = false;
        description = "Allow LAN access while using an exit node.";
      };

      advertiseConnector = mkOption {
        type = types.bool;
        default = false;
        description = "Advertise this node as a Tailscale app connector.";
      };

      sshAdvertise = mkOption {
        type = types.bool;
        default = true;
        description = "Advertise Tailscale SSH on this node.";
      };

      tags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "tag:server" ];
        description = "Tags to advertise (must be authorized by the tailnet ACL).";
      };

      hostname = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Override the hostname this node registers in Tailscale.";
      };

      encryptState = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Encrypt the tailscaled state file on disk via TPM 2.0. OFF by default
          here (our boxes are reinstalled/reflashed often, where a TPM can enter
          DA-lockout and crash-loop tailscaled per straylight's note). Turn on
          for stable servers with a healthy TPM.
        '';
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

  config = mkIf cfg.enable (
    let
      ts = cfg.tailscale;
      # "both" only when this node actually routes (advertises routes / exit
      # node); otherwise plain client. Avoids forcing routing features +
      # IP-forwarding onto workstations that don't need them.
      routes = ts.advertiseRoutes != [ ] || ts.advertiseExitNode;
    in
    {
      services.openssh = {
        enable = true;
      };

      services.tailscale = {
        enable = true;
        useRoutingFeatures = if routes then "both" else "client";
        openFirewall = true;

        # Declarative enrollment when an auth key is provided.
        authKeyFile = mkIf (ts.authKeyFile != null) ts.authKeyFile;

        extraDaemonFlags = lib.optional (!ts.encryptState) "--encrypt-state=false";

        extraUpFlags = lib.flatten [
          (lib.optional ts.acceptRoutes "--accept-routes")
          (lib.optional ts.acceptDNS "--accept-dns")
          (lib.optional (!ts.sshAdvertise) "--ssh=false")
          (lib.optional (ts.hostname != null) "--hostname=${ts.hostname}")
          (lib.optional (
            ts.advertiseRoutes != [ ]
          ) "--advertise-routes=${lib.concatStringsSep "," ts.advertiseRoutes}")
          (lib.optional (ts.tags != [ ]) "--advertise-tags=${lib.concatStringsSep "," ts.tags}")
          (lib.optional ts.advertiseExitNode "--advertise-exit-node")
          (lib.optional ts.acceptExitNode "--exit-node-allow-lan-access")
          (lib.optional ts.advertiseConnector "--advertise-connector")
        ];
      };

      # Throughput tuning for the default NIC (straylight): UDP GRO forwarding
      # materially improves tailscale wireguard throughput on many drivers.
      systemd.services.tailscale-ethtool = {
        description = "tune ethtool offloads for Tailscale throughput";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          NETDEV=$(${pkgs.iproute2}/bin/ip -o route get 8.8.8.8 2>/dev/null | ${pkgs.coreutils}/bin/cut -f5 -d' ')
          if [ -n "$NETDEV" ]; then
            ${pkgs.ethtool}/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off || true
          fi
        '';
      };

      # IP forwarding only when this node actually routes traffic.
      boot.kernel.sysctl = mkIf routes {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
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

        # tailscale0 is already a trustedInterface above (all traffic allowed);
        # the previous `interfaces.tailscale0.allowAll` was an invalid option and
        # redundant — removed. Per-service interface-scoped ports (e.g. postgres
        # 5432 on tailscale0) merge in cleanly via networking.firewall.interfaces.
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
    }
  );
}
