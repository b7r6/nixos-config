# nl-<site>-<x> — a cache node: the railgun shape without railgun's homelab.
# Its own one-host NativeLink site (scheduler + CAS shard + three
# workers, per fleet.dhall `producerHost`) and the Nix binary cache as an R2
# PRODUCER, so the four such hosts serve one cache from one durable tier.
#
# One per Azure region (the regions that would sell this subscription a
# 64-core box, 2026-10-23), so a site never spans regions. Installed with
# nixos-anywhere from railgun (the host key is pre-generated and shipped with
# --extra-files, so agenix decrypts on first boot); later deploys build on
# railgun and copy over the tailnet. No bootstrap variant.
{ name, site }:
{ flake, lib, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self disko agenix;
in
{
  imports = [
    self.nixosModules.default
    agenix.nixosModules.default
    disko.nixosModules.disko
    ../nl-az/disko.nix # gen2 Azure VM, single SCSI OS disk (/dev/sda): 1 GiB ESP + ext4 root
  ];

  networking.hostName = name;

  # Azure platform (Hyper-V guest, serial console, headless). The module forces
  # the home config off, which is what a cache node wants.
  hyper-modern-nixos.azure.enable = true;
  # Declarative tailnet enrolment: the network module only points at the key
  # file; each host declares the secret itself (as shannon and weyl do).
  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # ── The Nix cache, as a producer (same R2 tier and signing key as railgun) ─
  # The Azure module mkForces the nix_cache + watcher off (soak nodes never
  # build); mkOverride 40 beats its mkForce (50), as on railgun. 512 GiB fast
  # tier of the 2 TiB disk; what it holds is in R2 regardless.
  age.secrets.nativelink-r2-env.file = ../../../secrets/agenix/machines/nativelink-r2-env.age;
  hyper-modern-nixos.nativelink.r2 = {
    enable = true;
    accountId = "6063b6652178f5cf1cfb87e7e41acf1e";
    bucket = "straylight-nativelink-cas";
    environmentFile = "/run/agenix/nativelink-r2-env";
  };
  hyper-modern-nixos.nativelink.nixCache = {
    enable = lib.mkOverride 40 true;
    watchStore = lib.mkOverride 40 true;
    pushToR2 = true;
    fastCacheBytes = 549755813888; # 512 GiB
    upstreamCaches = [
      {
        url = "https://cache.nixos.org";
        trustedPublicKeys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
      }
      {
        url = "https://nix-community.cachix.org";
        trustedPublicKeys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
      }
    ];
  };

  # ── NativeLink RE: scheduler + CAS shard + three workers (fleet.dhall) ─────
  hyper-modern-nixos.nativelink = {
    enable = true;
    dhallHost = name;
    split = {
      enable = true;
      workers = 3;
    };
    openFirewall = true; # tailscale0 only, per the module
  };
  # The rendered config dials the host by its fleet fqdn; a one-host site only
  # ever dials itself, so pin it to loopback (as railgun does) and no zone is
  # needed for the site to work.
  networking.hosts."127.0.0.1" = [ "${name}.${site}.s4.gl" ];

  # Telemetry to railgun's OTel gateway over the tailnet (the wall lives there).
  hyper-modern-nixos.observability.otel.agent = {
    enable = true;
    gatewayEndpoint = "railgun:4317";
  };

  nix.settings = {
    max-jobs = "auto";
    cores = 0;
    min-free = lib.mkDefault (40 * 1024 * 1024 * 1024);
    max-free = lib.mkDefault (200 * 1024 * 1024 * 1024);
  };
  services.openssh.settings.MaxStartups = "50:30:100";

  system.stateVersion = "25.11";
}
