{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelParams = [ "amd_pstate=active" ];
  powerManagement.cpuFreqGovernor = "performance";
  services.thermald.enable = true;

  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
  };

  networking.hostName = "watchtower";
  networking.networkmanager.enable = true;

  # watchtower hosts the shared postgres (and atticd). Unlike the rest of the
  # fleet (firewall off), it re-enables its firewall so the postgres module's
  # interface-scoped 5432 rule (tailscale0 only) actually takes effect.
  hyper-modern-nixos.network.firewall.enable = true;

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    # RADV is now the default Vulkan driver
  };

  time.timeZone = "America/New_York";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # ── Central cache node: monolithic-shared (the fleet backend) ───────────────
  # watchtower hosts the single shared postgres + the monolithic atticd that
  # runs migrations + serves + the ONLY garbage collector (gc can't be
  # replicated). The `monolithic-shared` profile bundles all of that: it enables
  # the tailnet-reachable postgres (atticd role+db, md5 from the tailnet CIDRs),
  # connects atticd over loopback, and backs storage with R2. The env file
  # carries the RS256 secret, PGPASSWORD (sqlx reads it), and the R2 AWS_* creds
  # — none touch the store. The pg role password is set out-of-band once (see
  # the deploy runbook). Replicas elsewhere point at this postgres over MagicDNS.
  age.secrets.atticd-rs256.file = ../../../secrets/agenix/machines/atticd-rs256.age;
  age.secrets.attic-push-token.file = ../../../secrets/agenix/machines/attic-push-token.age;

  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "monolithic-shared";
  };

  system.stateVersion = "25.05";
}
