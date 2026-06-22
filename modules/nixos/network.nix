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

      exitNode = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "us-mia-wg-001.mullvad.ts.net";
        description = ''
          Pin the exit node this host routes through (the node's MagicDNS name or
          tailscale IP). Mainly for Mullvad-via-Tailscale exit nodes (enable the
          Mullvad add-on in the admin console first).

          Applied via a `tailscale set` ONESHOT (tailscale-exit-node.service),
          NOT via `tailscale up` flags — exit-node is a runtime, per-device knob,
          so `set` is the idiomatic path and doesn't get clobbered by re-running
          `up`. Flip at runtime any time with `tailscale set --exit-node=<node>`
          (or `--exit-node=` to clear); a rebuild re-asserts whatever is pinned
          here (null = explicitly cleared). Always pairs with
          --exit-node-allow-lan-access so the LAN/tailnet stays reachable.
        '';
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
        description = ''
          Enable the host firewall with Tailscale-aware rules. ON fleet-wide by
          default: tailscale0 is a trustedInterface (all tailnet traffic allowed),
          so this never blocks tailnet/SSH — it only closes the PUBLIC interfaces.

          This is the ENFORCEMENT layer for the fleet's "tailnet-only services"
          posture: every service module opens its port via
          networking.firewall.interfaces.tailscale0.allowedTCPPorts, which is a
          no-op unless the firewall is on. With it off, services that bind broadly
          (0.0.0.0/[::]) are reachable on every interface — so keep this ON unless
          a host has a deliberate reason not to.
        '';
      };

      nftables = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Use the modern nftables backend (networking.nftables.enable) instead of
          the iptables-nft compatibility shim. Safe fleet-wide here: all rules are
          expressed through high-level networking.firewall.* options (no raw
          iptables / extraCommands anywhere), which the nftables backend renders
          natively. Gives a single, inspectable `nft list ruleset`.
        '';
      };
    };

    mullvadDaemon = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Run the Mullvad VPN DAEMON (services.mullvad-vpn). OFF by default.

          The daemon installs an nftables KILLSWITCH (a `table inet mullvad` with
          `policy drop` chains that only permit traffic via `wg0-mullvad`). When
          it's enabled but NOT connected to a relay — our situation, since we
          route Mullvad via Tailscale's exit-node add-on, not this daemon — that
          lockdown can be (re)applied on boot/network-change with no wg0-mullvad
          interface up, STRANDING the host's network (remediated by hand with
          `nft flush ruleset`). So we keep the daemon off fleet-wide. Turn it on
          ONLY on a host that genuinely uses the Mullvad daemon directly.
        '';
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

      # Exit-node selection via `tailscale set` (NOT up flags) so it's a clean
      # runtime knob that a rebuild re-asserts without clobbering manual `set`s.
      # Only emitted when a node is pinned — to CLEAR a pin, set exitNode=null
      # AND run `tailscale set --exit-node=` once by hand. Ordered after
      # tailscaled so the daemon + MagicDNS are up.
      systemd.services.tailscale-exit-node = mkIf (ts.exitNode != null) {
        description = "route this host through the Tailscale exit node ${ts.exitNode}";
        after = [
          "tailscaled.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        requires = [ "tailscaled.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${config.services.tailscale.package}/bin/tailscale set \
            --exit-node=${ts.exitNode} --exit-node-allow-lan-access \
            || echo "warning: failed to set exit-node ${ts.exitNode}" >&2
        '';
      };

      # Apply accept-dns via `tailscale set` (NOT just up flags) so it takes on
      # the RUNNING daemon at every activation. up-flags only apply on first `up`;
      # a host that flips acceptDNS later (e.g. when it starts owning its resolver
      # via CoreDNS) needs `set` to re-assert it, or tailscaled keeps managing
      # resolv.conf (CorpDNS stays true). Ordered after tailscaled.
      systemd.services.tailscale-accept-dns = {
        description = "apply tailscale --accept-dns=${if ts.acceptDNS then "true" else "false"}";
        after = [
          "tailscaled.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        requires = [ "tailscaled.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${config.services.tailscale.package}/bin/tailscale set \
            --accept-dns=${if ts.acceptDNS then "true" else "false"} \
            || echo "warning: failed to set --accept-dns" >&2
        '';
      };

      # IP forwarding only when this node actually routes traffic.
      boot.kernel.sysctl = mkIf routes {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      # Mullvad DAEMON: off by default (its killswitch nft ruleset strands the
      # network on boot when enabled-but-disconnected — see mullvadDaemon option).
      # We route Mullvad via Tailscale's exit-node add-on, not this daemon.
      services.mullvad-vpn = mkIf cfg.mullvadDaemon.enable {
        enable = true;
        package = pkgs.mullvad-vpn;
      };

      # Modern nftables backend (single inspectable ruleset). Gated on the
      # firewall being on — there's no point selecting a backend for a disabled
      # firewall, and it keeps `nftables.enable` from fighting other ad-hoc
      # iptables users on a host that deliberately runs firewall-off.
      networking.nftables.enable = mkIf (cfg.firewall.enable && cfg.firewall.nftables) true;

      networking.firewall = {
        inherit (cfg.firewall) enable;

        # tailscale0 trusted ⇒ ALL tailnet traffic is allowed regardless of the
        # allowed*Ports below. So enabling the firewall never blocks the tailnet
        # or tailnet-scoped service ports; it only closes the PUBLIC interfaces.
        trustedInterfaces = mkIf cfg.firewall.enable [ "tailscale0" ];

        # Ports open on ALL interfaces (incl. public). Keep this list minimal —
        # it's the public attack surface. SSH (22) so a host is never locked out;
        # 3000 for the dev/preview server. Tailnet-only services do NOT belong
        # here — they use networking.firewall.interfaces.tailscale0.* instead.
        #
        # To EXPOSE a service to the public internet, prefer `tailscale serve`
        # (tailnet HTTPS) or `tailscale funnel` (public HTTPS) terminating at the
        # tailscaled proxy — the service itself stays bound to loopback/tailnet
        # and you never punch a hole here. Only add a port below for the rare
        # service that must face the raw internet directly.
        allowedTCPPorts = mkIf cfg.firewall.enable [
          22
          3000
        ];

        # 41641/udp is Tailscale's WireGuard port (direct connections / NAT
        # traversal). services.tailscale.openFirewall already opens it; listed
        # here for clarity/idempotence.
        allowedUDPPorts = mkIf cfg.firewall.enable [ 41641 ];

        # "loose" RPF: tailnet/WireGuard traffic can arrive asymmetrically; strict
        # RPF would drop it. Required for a node that also routes (exit/subnet).
        checkReversePath = mkIf cfg.firewall.enable "loose";

        # Per-service interface-scoped ports (e.g. postgres 5432, attic 8080 on
        # tailscale0) merge in via networking.firewall.interfaces.tailscale0.* —
        # those only take effect because the firewall is enabled.
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

      environment.systemPackages =
        (with pkgs; [
          wget
          ethtool
          curl
          dig
          inetutils
          nmap
          tailscale
          traceroute
        ])
        # the mullvad CLI/package only ships alongside its daemon.
        ++ lib.optional cfg.mullvadDaemon.enable pkgs.mullvad-vpn;
    }
  );
}
