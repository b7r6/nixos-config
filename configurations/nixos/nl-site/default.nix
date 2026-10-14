# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                             // hyper-modern-nixos // nl-site
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The generic host of a soak SITE: the generalization of configurations/nixos/
# nl-az/ (one hand-written site) to every site of hypermodern-nativelink's
# sites.dhall. configurations/sites.nix instantiates it once per host:
#
#   import ../nl-site { site = <rendered site>; host = "<name>"; role = …; package = …; }
#
#   node     scheduler / CAS shard / worker per the Dhall fleet (dhallHost = host)
#   rig      the soak driver (rechaos gateway + monkey + workload + oracle) and
#            the site's observability sink (ClickHouse + OTel gateway + Grafana)
#   builder  a transient x86_64 remote builder / deploy host; no NativeLink,
#            no tailnet, no site secrets — it only needs nix and ssh
#
# `site` is the JSON render of the site (render-sites.dhall): names, tailnet
# suffix, tags, the scheduler's fqdn, the CAS env secret name. `package` is the
# NativeLink binary the site soaks (null = the fork module's default), chosen
# by sites.nix from the flake input the site's `nativelinkRev` names. The Dhall
# fleet the nodes render is the FLAKE's (examples/fleet.dhall over
# examples/sites.dhall), so a site's topology lives in exactly one place.
#
{
  site,
  host,
  role ? "node",
  package ? null,
}:
{ flake, lib, ... }:
let
  inherit (flake) inputs;
  inherit (inputs)
    self
    disko
    agenix
    hypermodern-nativelink
    ;

  # This host's VM size from the site (nodes, rig or builder), and the OS disk
  # device that generation presents (v6 = NVMe; see ./disko.nix).
  machine =
    lib.findFirst (m: m.name == host) (throw "nl-site: ${host} is not in site ${site.name}") (
      site.nodes
      ++ [
        site.rig
        site.builder
      ]
    );
  nvme = lib.hasSuffix "_v6" machine.size;
in
{
  imports = [
    self.nixosModules.default
    agenix.nixosModules.default
    disko.nixosModules.disko
    (import ./disko.nix { device = if nvme then "/dev/nvme0n1" else "/dev/sda"; })
    (import ./common.nix { inherit site role; })
  ]
  ++ (
    if role == "rig" then
      [
        hypermodern-nativelink.nixosModules.site-secrets # tailnet key (+ CAS env, opted out below)
        ../../../modules/flake/nativelink/soak/rig.nix
        # The site's observability sink: ClickHouse + OTel gateway + Grafana.
        # Shared with the hand-written az site verbatim (it is self-contained:
        # loopback ClickHouse, the agents are pointed at the rig by common.nix);
        # it moves here when az folds onto nl-site.
        ../nl-az/rig.nix
        {
          hyper-modern-nativelink.siteSecrets.casEnv = false; # the rig runs no NativeLink; not a recipient
          hyper-modern-nixos.network.tailscale.tags = [ site.tags.rig ]; # site policy: 22 + NativeLink ports into the nodes
          hyper-modern-nixos.soakRig = {
            enable = true;
            targetHost = site.schedulerFqdn; # the site's scheduler, on the site's tailnet
            expectedWorkers = builtins.length site.nodes;
          };
        }
      ]
    else if role == "builder" then
      [ ./builder.nix ]
    else
      [
        hypermodern-nativelink.nixosModules.site-secrets
        (import ./node.nix { inherit site host package; })
      ]
  );
  networking.hostName = host;
  # v6: the OS disk is NVMe; the Azure module's initrd set is the v5 SCSI one.
  boot.initrd.availableKernelModules = lib.mkIf nvme [ "nvme" ];
}
