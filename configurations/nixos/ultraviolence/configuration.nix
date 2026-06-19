{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
  ];

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────
  # Two agenix secrets decrypt at boot to /run/agenix/:
  #   restic-password : the repo encryption passphrase
  #   restic-r2-env   : env file carrying this host's RESTIC_REPOSITORY, scoped
  #                     to a PER-MACHINE prefix in one shared bucket:
  #                       s3:https://<acct>.r2.cloudflarestorage.com/<bucket>/ultraviolence
  #                     + AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / REGION
  # The repo URL lives in the env file (not here) to keep the R2 account id out
  # of the nix store. Do the FIRST `restic init`/backup BY HAND (see BACKUP.md)
  # before flipping enable = true; the timer then drives the same repo.
  age.secrets.restic-password.file = ../../../secrets/agenix/machines/restic-password.age;
  age.secrets.restic-r2-env.file = ../../../secrets/agenix/machines/restic-r2-env.age;

  # Root-readable copy of the SAME rclone.conf (R2 remote + creds) for the
  # system mount service. The encrypted file is the user secret, but it's
  # encrypted to all host keys too, so the host can decrypt it at the NixOS
  # level into /run/agenix/rclone-conf (root, 600). The user gets its own copy
  # at ~/.config/rclone/rclone.conf via the home-manager agenix module.
  age.secrets.rclone-conf.file = ../../../secrets/agenix/users/b7r6/rclone-conf.age;

  hyper-modern-nixos.backup = {
    enable = true;
    # repository intentionally left empty: RESTIC_REPOSITORY comes from the env file.
    passwordFile = "/run/agenix/restic-password";
    environmentFile = "/run/agenix/restic-r2-env";
    # First R2 backup is scoped to /home only to validate the path with a
    # smaller upload; widen to /etc + /var/lib once the repo is trusted.
    paths = [ "/home" ];
  };

  # ── system-wide rclone mount of the R2 bucket ───────────────────────────────
  # Mounts the straylight-r2 remote at /mnt/r2 for any user/service. Uses the
  # root-decrypted rclone.conf above. Dedicated `host-mount` bucket (separate
  # from the restic `backups-restic` bucket), per-host path so each machine
  # gets its own subtree: host-mount:host-mount/<hostname>.
  hyper-modern-nixos.rcloneMount = {
    enable = true;
    configPath = "/run/agenix/rclone-conf";
    mounts.r2 = {
      remote = "straylight-r2:host-mount/ultraviolence";
      where = "/mnt/r2";
    };
  };

  # ── attic binary cache (tailnet, self-populating) ───────────────────────────
  # atticd binds all interfaces but the port is opened only on tailscale0, so
  # the `hypermodern` cache is reachable across the tailnet (public-pull) but
  # not the open internet. RS256 signing secret + a push-scoped token come from
  # agenix. The clientCache block makes THIS host both consult the cache first
  # (substituter, priority 10) and push every successful build into it.
  age.secrets.atticd-rs256.file = ../../../secrets/agenix/machines/atticd-rs256.age;
  age.secrets.attic-push-token.file = ../../../secrets/agenix/machines/attic-push-token.age;

  hyper-modern-nixos.attic = {
    enable = true;
    environmentFile = "/run/agenix/atticd-rs256";
    listen = "[::]:8080";
    trustedInterfaces = [ "tailscale0" ];

    # Back the cache with Cloudflare R2 (dedicated bucket). AWS_ACCESS_KEY_ID /
    # AWS_SECRET_ACCESS_KEY live in the atticd-rs256 env file alongside the
    # RS256 secret; bucket/endpoint are non-secret.
    storage = {
      type = "s3";
      region = "auto";
      bucket = "straylight-attic-cache";
      endpoint = "https://6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com";
    };

    clientCache = {
      enable = true;
      name = "hypermodern";
      endpoint = "http://ultraviolence.osiris-walleye.ts.net:8080";
      publicKey = "hypermodern:IxmiCAZWTeYmnOafmhz39qrn0wXj+aNvBy9dczJTcAs=";
      pushTokenFile = "/run/agenix/attic-push-token";
    };
  };

  # ── NativeLink remote execution (single-box monolithic bringup) ─────────────
  # CAS + scheduler + a local x86_64 worker, all on this host. Split the aarch64
  # worker out to shimmer later by adding role = "worker" there pointing at this
  # host's worker_api over the tailnet. Builds from source (~1000 derivations)
  # unless nativelink.cachix.org is added in modules/nixos/common/nix.nix.
  hyper-modern-nixos.nativelink = {
    enable = true;
    role = "monolithic";
    # loopback-only public API for the single-box bringup; widen when splitting.
    publicListen = "127.0.0.1:50051";
    workerApiListen = "127.0.0.1:50061";
    workerApiEndpoint = "grpc://127.0.0.1:50061";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/8d797692-927e-46c4-8047-0c9ea975a41f";
    fsType = "btrfs";
    options = [
      "subvol=@"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
      "ssd"
      "discard=async"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8959-4D56";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  hyper-modern-nixos.hyper-wayland = {
    enable = true;
  };

  hyper-modern-nixos.nvidia = {
    enable = true;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.enableRedistributableFirmware = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # Bluetooth management GUI
  services.blueman.enable = true;

  # CPU and system optimizations
  boot.kernelParams = [ "pcie_aspm=off" ];
  powerManagement.cpuFreqGovernor = "performance";
  hardware.cpu.amd.updateMicrocode = true;

  networking.hostName = "ultraviolence";
  networking.networkmanager.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services.thermald.enable = true;

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

  # ── Per-host display config ────────────────────────────────────────────────

  home-manager.users.b7r6 = {
    hyper-modern-nixos = {
      hyprland.monitors = {
        left = {
          description = "ASUSTek COMPUTER INC PG32UCDP SCLMQS022729";
          resolution = "3840x2160";
          refreshRate = 120;
          position = "0x0";
          scale = 1.5;
          workspaces = [
            1
            2
            3
            4
            5
          ];
        };
        center = {
          description = "ASUSTek COMPUTER INC PG32UCDP T1LMQS044820";
          resolution = "3840x2160";
          refreshRate = 120;
          position = "2560x0";
          scale = 1.5;
          workspaces = [
            6
            7
            8
            9
            10
          ];
          primary = true;
        };
        right = {
          description = "LG Electronics LG ULTRAGEAR+ 502NTMX7E483";
          resolution = "3840x2160";
          refreshRate = 144;
          position = "5120x0";
          scale = 1.5;
          workspaces = [
            11
            12
            13
            14
            15
          ];
        };
      };

      themes.display = {
        profile = "lg-ultragear-oled";
        highDPI = true;
        width = 3840;
        height = 2160;
      };
    };
  };

  system.stateVersion = "25.05";
}
