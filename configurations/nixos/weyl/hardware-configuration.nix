{ config, lib, pkgs, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # TODO[b7r6]: move this shit to disko...
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/e0cab5b4-040d-47a9-8b87-9575d275aa17";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/4C1D-B8D4";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  # =====================================================
  # asus specific
  # =====================================================

  boot.initrd.kernelModules = [ ];

  boot.kernelModules = [ "kvm-amd" ];
  boot.kernelPackages = pkgs.linuxPackages_testing;
  boot.kernelParams = [ "mem_sleep_default=deep" ];
  boot.blacklistedKernelModules = [ "ucsi_acpi" ];

  boot.initrd.availableKernelModules =
    [ "nvme" "xhci_pci" "thunderbolt" "usbhid" "sdhci_pci" ];

  hardware.cpu.amd.updateMicrocode = true;
  powerManagement.cpuFreqGovernor = "performance";
  services.supergfxd.enable = true;
  systemd.services.supergfxd.path = [ pkgs.pciutils ];

  services.asusd = {
    enable = true;
    enableUserService = true;
  };

  environment.systemPackages = with pkgs; [ ryzenadj ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
