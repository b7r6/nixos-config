{
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # TODO[b7r6]: move this shit to disko...
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/620c4624-cf8f-4b3c-91eb-1fe8b73924b6";
    fsType = "btrfs";
    options = [ "subvol=@" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/2920-8012";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [ ];

  # =====================================================
  # asus specific
  # =====================================================

  boot.initrd.kernelModules = [ ];

  boot.kernelModules = [ "kvm-amd" ];
  boot.kernelParams = [ "mem_sleep_default=deep" ];
  boot.blacklistedKernelModules = [ "ucsi_acpi" ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usbhid"
    "sdhci_pci"
  ];

  hardware.cpu.amd.updateMicrocode = true;
  # With amd-pstate-epp, `powersave` + the default balance_performance EPP
  # still boosts to max clocks but lets the platform back off under thermal
  # pressure — `performance` pins EPP and rides the thermal limit, which this
  # chassis can't sustain (hard crashes under all-core builds).
  powerManagement.cpuFreqGovernor = "powersave";
  services.supergfxd.enable = true;
  systemd.services.supergfxd.path = [ pkgs.pciutils ];

  services.asusd = {
    enable = true;
  };

  environment.systemPackages = with pkgs; [ ryzenadj ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
