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

  boot.kernelModules = [
    "kvm-amd"
    "amdgpu"
  ];

  boot.extraModulePackages = [ ];
  boot.kernelPackages = pkgs.linuxPackages_testing;

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/ace59556-eb5a-45ed-86d6-2785ce98ef5b";
    fsType = "btrfs";
    options = [ "subvol=@" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/1393-0F2D";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # hardware.amdgpu.strixHalo = lib.mkDefault true;
}
