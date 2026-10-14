# Azure gen2 VM: the OS disk is the only disk (D*s_v5 has no temp disk), so it
# is /dev/sda unambiguously. 1 GiB ESP + ext4 root. nixos-anywhere applies this
# from the kexec installer; later deploys never touch it.
{
  disko.devices.disk.os = {
    device = "/dev/sda";
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
