# One OS disk per VM, ESP + ext4 root. Its device name depends on the VM
# generation: D*s_v5 (no temp disk) presents it over Hyper-V SCSI as
# /dev/sda; D*s_v6 presents it over NVMe as /dev/nvme0n1 (and needs the
# nvme driver in the initrd, see common.nix). nixos-anywhere applies this
# from the kexec installer; later deploys never touch it.
{ device }:
{
  disko.devices.disk.os = {
    inherit device;
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
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
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
