# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // shannon // disko // LUKS root
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Full-disk encryption for the SOC2 root-encryption control. 1G ESP + a LUKS2
# container holding btrfs with the @/@home subvols (matching the pre-encryption
# layout so a restic /home restore lands correctly). Interactive passphrase at
# boot — no keyfile, no TPM (the compliance-standard choice; shannon has a
# screen). Applied ONLY at (re)install: `disko --mode disko .../disko.nix`.
{
  disko.devices.disk.main = {
    device = "/dev/nvme0n1";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          label = "boot";
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        luks = {
          label = "luks";
          size = "100%";
          content = {
            type = "luks";
            name = "cryptroot";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [
                "-L"
                "nixos"
                "-f"
              ];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                # Real swap, inside the LUKS container. The installer has no
                # swap of its own and the box hangs silently when a build
                # exhausts RAM; disko creates+activates this during
                # `--mode format,mount`, so nixos-install already has it. At
                # runtime it backs zram (modules: zramSwap 50%) as the
                # last-resort tier for large builds. Encrypted by construction.
                "@swap" = {
                  mountpoint = "/.swap";
                  mountOptions = [ "noatime" ];
                  swap.swapfile.size = "32G";
                };
              };
            };
          };
        };
      };
    };
  };
}
