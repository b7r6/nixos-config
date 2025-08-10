{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sdhci_pci"
  ];

  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];

  boot.extraModulePackages = [ ];
  boot.kernelPackages = pkgs.linuxPackages_testing;

  # CPU optimizations for Ryzen 9 9950X3D
  boot.kernelParams = [
    # AMD CPU optimizations
    # "amd_pstate=active"
    # "amd_pstate.shared_mem=1"
    # "processor.max_cstate=1"
    # "idle=nomwait"

    # # Memory optimizations
    # "transparent_hugepage=always"
    # "hugepagesz=1G"
    # "hugepages=16"

    # # IOMMU for virtualization
    # "iommu=pt"
    # "amd_iommu=on"

    # # NVIDIA Wayland support
    # "nvidia-drm.modeset=1"
    # "nvidia-drm.fbdev=1" # For better Wayland compatibility

    # # General performance
    # "mitigations=off"
    # "nowatchdog"
    # "nmi_watchdog=0"
  ];

  # Power management optimizations
  powerManagement.cpuFreqGovernor = "performance";

  # AMD microcode updates
  hardware.cpu.amd.updateMicrocode = true;

  # Btrfs optimizations
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

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  # Network and system performance tuning
  boot.kernel.sysctl = {
    # Network optimizations
    "net.core.default_qdisc" = "fq_codel";
    "net.ipv4.tcp_congestion" = "bbr";
    "net.core.netdev_max_backlog" = 16384;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 87380 134217728";
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";

    # VM optimizations
    # "vm.swappiness" = 10;
    # "vm.vfs_cache_pressure" = 50;
    # "vm.dirty_ratio" = 10;
    # "vm.dirty_background_ratio" = 5;
    # "vm.max_map_count" = 2147483642;
  };

  # Firmware updates
  services.fwupd.enable = true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
