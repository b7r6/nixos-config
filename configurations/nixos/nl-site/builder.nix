# The site's builder: a transient D16s_v5 that is (i) a Nix remote builder
# for the operator's laptop over ssh (`nix build --builders 'ssh://…'`, the
# line azure-soak.sh prints after `builder up`) and (ii) a box a checkout can
# deploy FROM so closures move at Azure speed instead of a laptop uplink.
# No NativeLink, no tailnet, no site secret: it needs nix, ssh and disk.
# Deallocated when idle (`builder down`); recreated from the same host key.
{ lib, ... }:
{
  # The operator's laptop drives `nix-daemon` here as its own user (the
  # registry's accounts + keys), so that user must be trusted to push paths
  # and set builder-side options; wheel already is fleet-wide.
  nix.settings = {
    max-jobs = "auto";
    cores = 0;
    # A build box with no desktop closure: keep the store lean between sites.
    min-free = lib.mkDefault (10 * 1024 * 1024 * 1024);
    max-free = lib.mkDefault (40 * 1024 * 1024 * 1024);
  };

  # Nothing to export: no OTel agent (common.nix leaves it off for the
  # builder), no state registry entries, no service of its own.
  services.openssh.settings.MaxStartups = "50:30:100"; # parallel nix copy / remote-build sessions
}
