{
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

  boot.kernelModules = [
    "kvm-amd"
    "btusb"
    "mt7921e"
  ];

  boot.extraModulePackages = [ ];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable firmware
  hardware.enableRedistributableFirmware = true;

  # Bluetooth configuration
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # boot.kernelPatches = [
  #   {
  #     name = "btusb-mt7927-support";
  #     patch = pkgs.writeText "btusb-mt7927.patch" ''
  #       --- a/drivers/bluetooth/btusb.c
  #       +++ b/drivers/bluetooth/btusb.c
  #       @@ -613,6 +613,10 @@ static const struct usb_device_id quirks_table[] = {
  #        	{ USB_DEVICE(0x04ca, 0x3801), .driver_info = BTUSB_MEDIATEK |
  #        						     BTUSB_WIDEBAND_SPEECH },

  #       +	/* MediaTek MT7927 */
  #       +	{ USB_DEVICE(0x0489, 0xe13a), .driver_info = BTUSB_MEDIATEK |
  #       +						     BTUSB_WIDEBAND_SPEECH },
  #       +
  #        	/* Additional MediaTek MT7668 Bluetooth devices */
  #        	{ USB_DEVICE(0x043e, 0x3109), .driver_info = BTUSB_MEDIATEK |
  #        						     BTUSB_WIDEBAND_SPEECH },
  #     '';
  #   }
  # ];

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

  boot.kernel.sysctl = {
    "net.core.default_qdisc" = "fq_codel";
    "net.ipv4.tcp_congestion" = "bbr";
    "net.core.netdev_max_backlog" = 16384;
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 87380 134217728";
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";
  };

  environment.systemPackages = with pkgs; [
    ryzenadj
  ];

  systemd.services.ryzen-power-limit = {
    description = "Set Ryzen power limits";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ryzenadj}/bin/ryzenadj --tctl-temp=85 --stapm-limit=120000 --fast-limit=140000 --slow-limit=130000";
    };
  };

  services.fwupd.enable = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
