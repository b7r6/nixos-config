{
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # fileSystems now come from ./disko.nix (LUKS + btrfs @/@home). The old
  # hand-written mounts lived here (the "move this to disko" TODO — done).

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
    # LUKS root: dm-crypt binds its AES implementation when the volume is
    # opened in the initrd and never re-binds. nixpkgs' luksroot module ships
    # "aes" (generic) but not the AES-NI driver, so without this the root disk
    # runs on software AES for the whole session (verified 2026-10-11: the
    # installed initrd had no aesni-intel.ko).
    "aesni_intel"
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
