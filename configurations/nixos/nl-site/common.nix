# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // hyper-modern-nixos // nl-site common
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# What every VM of a site shares (the nl-az/common.nix shape, with the site's
# names as parameters): the Azure platform module, declarative enrollment on
# the SITE's tailnet, OTel agent → the site's rig by MagicDNS name, and the
# rig's root key so the soak driver can kill the scheduler over the tailnet
# (process chaos). The builder is the exception: a transient box off the
# tailnet, with no site secret to decrypt.
{ site, role }:
{ flake, lib, ... }:
let
  onTailnet = role != "builder";
  # the role's enrollment key (a tagged key enrolls the host already tagged)
  authKey = if role == "rig" then site.tailscaleAuthKeySecret.rig else site.tailscaleAuthKeySecret.nodes;
in
{
  hyper-modern-nixos.azure.enable = true;

  # ── Tailscale: declarative, from the SITE's auth-key secret ────────────────
  # The site's enrollment key (and the CAS SAS) are owned by hypermodern-
  # nativelink's agenix tree, imported via nixosModules.site-secrets in
  # ./default.nix — not this repo's global key. The secret name is the site's
  # (sites.dhall `tailscaleAuthKeySecret.<role>`, minted tagged per role by
  # `azure-soak.sh --site <s> tskey`), so a site on a tailnet of its own is
  # one field + two secrets away.
  hyper-modern-nixos.network.tailscale.authKeyFile = lib.mkIf onTailnet "/run/agenix/${authKey}";
  hyper-modern-nativelink.siteSecrets.tailscaleAuthKeyName = lib.mkIf onTailnet authKey;

  # ── OTel agent → the rig's gateway, by the SITE's MagicDNS name ────────────
  # The module's default endpoint is the registry's `ch`-tagged host on the
  # fleet tailnet, a name this tailnet cannot resolve. The site's sink is its
  # rig; the policy allows exactly nodes → rig:4317. On the rig itself the
  # gateway role is on, so the exporter is ClickHouse and this endpoint is
  # unused. The builder has no sink to reach and ships nothing.
  hyper-modern-nixos.observability.otel.agent = lib.mkIf onTailnet {
    enable = true;
    gatewayEndpoint = "${site.rigFqdn}:4317";
  };

  # ── The rig's root key (ssh <rig> → root@<nodes>) ──────────────────────────
  # Generated with the host keys (azure-soak.sh --site <s> up); the public
  # half is data in the site's flake (secrets/pub/<rig>-soak-root.pub), the
  # private half is shipped to the rig by nixos-anywhere --extra-files.
  # Tailnet-only reach. The builder authorizes nobody's root.
  users.users.root.openssh.authorizedKeys.keyFiles = lib.mkIf onTailnet [
    (flake.inputs.hypermodern-nativelink + "/secrets/pub/${site.rig.name}-soak-root.pub")
  ];

  system.stateVersion = "25.11";
}
