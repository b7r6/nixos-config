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

  # ── Central cache state: PostgreSQL (tailnet-reachable) ─────────────────────
  # watchtower hosts the single shared postgres that backs the fleet's atticd
  # metadata. It listens on loopback + the tailscale interface (firewall is off
  # fleet-wide; binding + pg_hba are the controls), permitting md5 auth from the
  # tailnet CGNAT range. The `atticd` role + database are created declaratively;
  # the role password is set out-of-band (see BACKUP.md / runbook) since NixOS
  # won't put a password in the store — atticd connects using the password baked
  # into ATTIC_SERVER_DATABASE_URL in its agenix env file.
  hyper-modern-nixos.databases.postgres = {
    enable = true;
    tailnet.enable = true;
    ensureDatabases = [ "atticd" ];
    ensureUsers = [
      {
        name = "atticd";
        ensureDBOwnership = true;
      }
    ];
  };

  # ── atticd: monolithic (api-server + the single garbage collector) ──────────
  # watchtower is the ONLY node that runs gc (gc cannot be replicated). Its
  # api-server is one of many across the fleet; all share this postgres + the R2
  # chunk store. The env file carries the RS256 secret, ATTIC_SERVER_DATABASE_URL
  # (with the postgres password), and the R2 AWS_* creds — none touch the store.
  age.secrets.atticd-rs256.file = ../../../secrets/agenix/machines/atticd-rs256.age;
  age.secrets.attic-push-token.file = ../../../secrets/agenix/machines/attic-push-token.age;

  hyper-modern-nixos.attic = {
    enable = true;
    mode = "monolithic";
    environmentFile = "/run/agenix/atticd-rs256";
    # watchtower IS the postgres host: connect over loopback. PGPASSWORD comes
    # from the env file (sqlx reads it); the URL itself is non-secret.
    databaseUrl = "postgresql://atticd@localhost/atticd";
    listen = "[::]:8080";
    trustedInterfaces = [ "tailscale0" ];

    storage = {
      type = "s3";
      region = "auto";
      bucket = "straylight-attic-cache";
      endpoint = "https://6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com";
    };

    # watchtower consults its OWN local api-server first, and pushes builds.
    clientCache = {
      enable = true;
      name = "hypermodern";
      endpoint = "http://localhost:8080";
      publicKey = "hypermodern:IxmiCAZWTeYmnOafmhz39qrn0wXj+aNvBy9dczJTcAs=";
      pushTokenFile = "/run/agenix/attic-push-token";
    };
  };

  system.stateVersion = "25.05";
}
