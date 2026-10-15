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

  # rtc_cmos is a module (CONFIG_RTC_DRV_CMOS=m, HCTOSYS=y): left to udev it
  # registers ~17s in, AFTER systemd has advanced the clock to the timesync
  # clock-file stamp, and hctosys sets it straight back to the RTC. On
  # 2026-10-15 a dead battery reset the RTC to 2024-10-29; services started on
  # that clock, NTP then stepped two years forward, and grafana's ngalert
  # ticker replayed every missed tick (180% CPU). Loaded in the initrd, the RTC
  # is read first and the later bumps can only move time forward.
  boot.initrd.kernelModules = [ "rtc_cmos" ];

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
