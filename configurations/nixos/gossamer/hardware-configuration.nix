# Hardware scan (GB10 DGX Spark — identical to shimmer)
{ lib, ... }: {
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "usbhid"
    "usb_storage"
  ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;
}
