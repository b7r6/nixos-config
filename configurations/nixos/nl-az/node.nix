# A fleet node of the Azure site: whatever the typed Dhall says this host is
# (nl-az-a: scheduler + CAS shard + worker; b/c: CAS shard + worker). The slow
# tier is Azure Blob through a SAS URL in the agenix env file; ports open on
# tailscale0 only (openFirewall), the ring and worker_api dial MagicDNS names.
{ name }:
{ ... }:
{
  # nativelink-azure-env (AZURE_CAS_SAS_URL) is declared by the site-secrets
  # module from hypermodern-nativelink (see ./default.nix).
  # The site policy (hypermodern-nativelink netops/tailscale-policy.hujson):
  # fleet nodes carry tag:nl-soak — ring + worker_api among themselves, 4317 to
  # the rig, nothing else.
  hyper-modern-nixos.network.tailscale.tags = [ "tag:nl-soak" ];

  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = name;
    openFirewall = true;
    extraEnvironmentFiles = [ "/run/agenix/nativelink-azure-env" ];
  };

  # ── Telemetry: the flake's contract, into the rig's ClickHouse ─────────────
  # With nativelink.enable the shim stamps identity by port (4321 →
  # nativelink.role=re) and scrapes 127.0.0.1:50052 + :50051 /metrics; what is
  # left is which logs ship. Only nativelink's unit: a chaos campaign makes it
  # chatty, and the rest of a node's journal is noise on a 128 GiB sink.
  hyper-modern-nixos.observability.otel.agent.journaldUnits = [ "nativelink.service" ];
}
