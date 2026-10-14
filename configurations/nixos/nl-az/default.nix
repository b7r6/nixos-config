# Shared host wrapper for the Azure soak fleet: every nl-az-* host dir's
# default.nix is `import ../nl-az { name = "<host>"; role = "node" | "rig"; }`.
#   node — scheduler/CAS/worker per the Dhall fleet (dhallHost = name)
#   rig  — the soak driver (rechaos gateway + monkey + workload + oracle)
{
  name,
  role ? "node",
}:
{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
  inherit (inputs)
    self
    disko
    agenix
    hypermodern-nativelink
    ;
  # The az site record (the flake's sites.dhall, rendered; IFD as in
  # sites.nix): the rig's egress-faults wiring reads it like nl-site does.
  site =
    (hypermodern-nativelink.lib.renderSites {
      pkgs = pkgs.buildPackages;
      sites = hypermodern-nativelink + "/examples/sites.dhall";
    }).az;
in
{
  imports = [
    self.nixosModules.default
    agenix.nixosModules.default
    hypermodern-nativelink.nixosModules.site-secrets # tailnet key + CAS SAS, owned by the site's flake
    disko.nixosModules.disko
    ./disko.nix
    ./common.nix
  ]
  ++ (
    if role == "rig" then
      [
        hypermodern-nativelink.nixosModules.soak-rig # the soak driver is the site flake's (continuous, savage)
        ./rig.nix # the site's observability sink: ClickHouse + OTel gateway + Grafana
        {
          # The rig runs no NativeLink; it holds the site's CAS env only when it
          # runs the egress fault proxy (sites.dhall egressFaults), which fronts
          # the Blob container with that SAS for the nodes.
          hyper-modern-nativelink.siteSecrets.casEnv = site.egressFaults;
          hyper-modern-nativelink.siteSecrets.casEnvName = site.casEnvSecret;
          hyper-modern-nixos.network.tailscale.tags = [ "tag:nl-rig" ]; # site policy: 22 + NativeLink ports into the nodes
          hyper-modern-nixos.soakRig = {
            enable = true;
            # The five classes: the egress fault proxy (class 4) as the site says;
            # the scheduler-scenario phase is on by the module's default.
            egressFaults = {
              enable = site.egressFaults;
              dialect = site.egressDialect;
              proxyUrl = site.egressProxy or ""; # dhall-to-json drops a None field
              listenPort = site.egressProxyPort;
              controlPort = site.egressControlPort;
              upstreamEnvFile = "/run/agenix/${site.casEnvSecret}";
            };
            targetHost = "nl-az-a.tail8ec1af.ts.net"; # the az site's scheduler, on the site's tailnet
            # One-hour campaigns while the wall is being shown: a completed,
            # loaded campaign every hour beats one two-hour run in flight.
            durationSeconds = 3600;
            casNodes = [
              "nl-az-b.tail8ec1af.ts.net"
              "nl-az-c.tail8ec1af.ts.net"
            ];
          };
          # The wall: this Grafana also reads az2's sink (datasource
          # `clickhouse-az2`) for the differential dashboard.
          hyper-modern-nixos.soakSink.grafana.fqdn = "nl-az-rig.tail8ec1af.ts.net"; # Grafana on the tailnet
          hyper-modern-nixos.soakSink.wall.peers = [
            {
              name = "az2";
              host = "nl-az2-rig.tail8ec1af.ts.net";
            }
          ];
        }
      ]
    else
      [ (import ./node.nix { inherit name; }) ]
  );
  networking.hostName = name;
}
