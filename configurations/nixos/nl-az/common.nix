# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                          // hyper-modern-nixos // nl-az common
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# What every Azure soak VM shares (docs/azure-soak-fleet.md): the Azure
# platform module, declarative tailnet enrollment, OTel agent → the fleet
# gateway, and the rig's root key so the soak driver can kill the scheduler
# over the tailnet (process chaos). The nativelink role itself is per host.
{ ... }:
{
  hyper-modern-nixos.azure.enable = true;

  # ── Tailscale: declarative, from the SITE's auth-key secret ────────────────
  # The Azure site lives on its own tailnet; its enrollment key (and the CAS
  # SAS) are owned by hypermodern-nativelink's agenix tree, imported via
  # nixosModules.site-secrets in ./default.nix — not this repo's global key.
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # ── OTel agent → the rig's gateway, by the SITE's MagicDNS name ────────────
  # The module's default endpoint is the registry's `ch`-tagged host on the
  # fleet tailnet (shannon.osiris-walleye.ts.net) — a name this tailnet cannot
  # resolve, let alone reach. The site's sink is the rig (configurations/nixos/
  # nl-az/rig.nix); the policy allows exactly nl-soak → nl-rig:4317. On the rig
  # itself the gateway role is on, so the exporter is ClickHouse and this
  # endpoint is unused.
  hyper-modern-nixos.observability.otel.agent = {
    enable = true;
    gatewayEndpoint = "nl-az-rig.tail8ec1af.ts.net:4317";
  };

  # ── The rig's root key (ssh nl-az-rig → root@nl-az-{a,b,c}) ─────────────────
  # Pre-generated with the host keys (sh/azure-soak.sh keys); private half is
  # shipped to the rig by nixos-anywhere --extra-files. Tailnet-only reach.
  users.users.root.openssh.authorizedKeys.keyFiles = [ ./rig-root-key.pub ];

  system.stateVersion = "25.11";
}
