{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

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
