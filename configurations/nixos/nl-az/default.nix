# Shared host wrapper for the Azure soak fleet: every nl-az-* host dir's
# default.nix is `import ../nl-az { name = "<host>"; role = "node" | "rig"; }`.
#   node — scheduler/CAS/worker per the Dhall fleet (dhallHost = name)
#   rig  — the soak driver (rechaos gateway + monkey + workload + oracle)
{ name, role ? "node" }:
{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self disko agenix hypermodern-nativelink;
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
        ../../../modules/flake/nativelink/soak/rig.nix
        ./rig.nix # the site's observability sink: ClickHouse + OTel gateway + Grafana
        {
          hyper-modern-nativelink.siteSecrets.casEnv = false; # the rig runs no NativeLink; not a recipient
          hyper-modern-nixos.network.tailscale.tags = [ "tag:nl-rig" ]; # site policy: 22 + NativeLink ports into the nodes
          hyper-modern-nixos.soakRig = {
            enable = true;
            targetHost = "nl-az-a.tail8ec1af.ts.net"; # the az site's scheduler, on the site's tailnet
          };
        }
      ]
    else
      [ (import ./node.nix { inherit name; }) ]
  );
  networking.hostName = name;
}
