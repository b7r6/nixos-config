# Shared host wrapper for the Azure soak fleet: every nl-az-* host dir's
# default.nix is `import ../nl-az { name = "<host>"; role = "node" | "rig"; }`.
#   node — scheduler/CAS/worker per the Dhall fleet (dhallHost = name)
#   rig  — the soak driver (rechaos gateway + monkey + workload + oracle)
{
  name,
  role ? "node",
}:
{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs)
    self
    disko
    agenix
    hypermodern-nativelink
    ;
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
          hyper-modern-nativelink.siteSecrets.casEnv = false; # the rig runs no NativeLink; not a recipient
          hyper-modern-nixos.network.tailscale.tags = [ "tag:nl-rig" ]; # site policy: 22 + NativeLink ports into the nodes
          hyper-modern-nixos.soakRig = {
            enable = true;
            targetHost = "nl-az-a.tail8ec1af.ts.net"; # the az site's scheduler, on the site's tailnet
            casNodes = [
              "nl-az-b.tail8ec1af.ts.net"
              "nl-az-c.tail8ec1af.ts.net"
            ];
          };
          # The wall: this Grafana also reads az2's sink (datasource
          # `clickhouse-az2`) for the differential dashboard.
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
