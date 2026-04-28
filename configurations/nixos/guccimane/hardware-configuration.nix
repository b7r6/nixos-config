{
  pkgs,
  lib,
  config,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "ahci"
  ];

  boot.kernelModules = [
    "kvm-amd"
    "btusb"
    "mt7921e"
  ];

  boot.extraModulePackages = [ ];
  boot.kernelPackages = pkgs.linuxPackages_testing;

  # Enable firmware
  hardware.enableRedistributableFirmware = true;

  # Bluetooth configuration
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

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
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/07c00684-d3a9-4543-a4c8-aa314c186a34";
    fsType = "btrfs";
    options = [
      "subvol=root"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
      "ssd"
      "discard=async"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/07c00684-d3a9-4543-a4c8-aa314c186a34";
    fsType = "btrfs";
    options = [
      "subvol=nix"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
      "ssd"
      "discard=async"
    ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/07c00684-d3a9-4543-a4c8-aa314c186a34";
    fsType = "btrfs";
    options = [
      "subvol=home"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
      "ssd"
      "discard=async"
    ];
  };

  fileSystems."/opt" = {
    device = "/dev/disk/by-uuid/07c00684-d3a9-4543-a4c8-aa314c186a34";
    fsType = "btrfs";
    options = [
      "subvol=opt"
      "compress=zstd:1"
      "noatime"
      "space_cache=v2"
      "ssd"
      "discard=async"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/8904-596D";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];
  networking.useDHCP = lib.mkDefault true;

  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq_codel";
    "net.ipv4.tcp_congestion" = "bbr";
    "net.core.netdev_max_backlog" = 16384;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 87380 134217728";
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";
  };

  services.fwupd.enable = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
