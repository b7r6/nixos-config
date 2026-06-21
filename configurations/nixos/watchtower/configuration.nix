{ flake, lib, ... }:
let
  inherit (flake) inputs;

  # ── Incremental rollout switches ────────────────────────────────────────────
  # First deploy brings up ONLY the safe baseline (tailscale declarative
  # enrollment + ssh), so we can confirm watchtower comes up healthy and stays
  # reachable. Then flip these on ONE AT A TIME, rebuilding + verifying between:
  #   1. enableInfra      -> postgres + monolithic atticd (the fleet cache backend)
  #   2. enableBackup     -> restic timer (after the by-hand `restic init`)
  # Keep both false for the initial infra-off deploy.
  enableInfra = true;
  enableBackup = false;
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

  # ── Tailscale safety net (ALWAYS on) ────────────────────────────────────────
  # Declarative enrollment so this remote box can't fall off the tailnet during
  # the incremental rollout — if a rebuild restarts tailscaled, it re-auths from
  # the key rather than stranding the node. Tested live on ultraviolence first.
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";

  # watchtower hosts the shared postgres (and atticd). Unlike the rest of the
  # fleet (firewall off), it re-enables its firewall so the postgres module's
  # interface-scoped 5432 rule (tailscale0 only) actually takes effect. Gated
  # with the infra rollout so the baseline deploy keeps the fleet firewall-off
  # default (no surprise port changes before the services exist).
  hyper-modern-nixos.network.firewall.enable = lib.mkIf enableInfra true;

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
  age.secrets = lib.mkMerge [
    # tailscale safety net: ALWAYS present
    { tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age; }
    (lib.mkIf enableInfra {
      atticd-rs256.file = ../../../secrets/agenix/machines/atticd-rs256.age;
      attic-push-token.file = ../../../secrets/agenix/machines/attic-push-token.age;
      attic-cache-keypair.file = ../../../secrets/agenix/machines/attic-cache-keypair.age;
    })
    (lib.mkIf enableBackup {
      restic-password.file = ../../../secrets/agenix/machines/restic-password.age;
      restic-r2-env.file = ../../../secrets/agenix/machines/restic-r2-env.watchtower.age;
    })
  ];

  hyper-modern-nixos.attic-node = lib.mkIf enableInfra {
    enable = true;
    profile = "monolithic-shared";
  };

  # ── restic → Cloudflare R2 backups ──────────────────────────────────────────
  # Per-host repo: s3:…/backups-restic/watchtower (isolated locks + retention).
  #   restic-password           : the repo encryption passphrase (shared secret)
  #   restic-r2-env.watchtower  : RESTIC_REPOSITORY + R2 AWS_* creds for THIS host
  # FIRST run is BY HAND (see BACKUP.md) before this timer touches anything:
  #   sudo RESTIC_PASSWORD_FILE=/run/agenix/restic-password \
  #     env $(cat /run/agenix/restic-r2-env | xargs) restic init
  #   …then one manual `restic backup /home` + `restic snapshots` to verify,
  #   THEN flip enable = true and rebuild.
  # Starting with /home only to validate the path with a small upload; widen to
  # /etc + /var/lib (incl. the atticd metadata under /var/lib) once trusted.
  # (restic secrets are declared in the age.secrets mkMerge above, gated on
  # enableBackup.)
  hyper-modern-nixos.backup = lib.mkIf enableBackup {
    enable = true;
    passwordFile = "/run/agenix/restic-password";
    environmentFile = "/run/agenix/restic-r2-env";
    paths = [ "/home" ];
  };

  system.stateVersion = "25.05";
}
