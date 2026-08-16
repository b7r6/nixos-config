# Jetson AGX Thor disk layout - 1G ESP + ext4 root on the 1TB NVMe.
#
# This matches the on-disk reality from the 2026-08-06 re-image; disko only
# re-applies it at re-image time (nixos-anywhere --phases disko,install).
# The ESP keeps the GPT name "esp" for the JetPack capsule-update convention
# and mounts nofail so a headless box degrades to a stale bootloader instead
# of emergency mode. The factory 16-partition JetPack GPT is archived
# byte-exact on shimmer (~/jetson-factory-backup) if it is ever wanted back.
{
  disko.devices.disk.nvme = {
    device = "/dev/nvme0n1";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        esp = {
          label = "esp";
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot/efi";
            mountOptions = [
              "nofail"
              "umask=0077"
            ];
          };
        };

        root = {
          label = "nixos";
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [
              "-L"
              "nixos"
            ];
            mountpoint = "/";
          };
        };
      };
    };
  };
}
