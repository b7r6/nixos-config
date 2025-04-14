# ProArt P16 Testing ISO

This is a testing ISO for the ASUS ProArt P16 laptop that includes configurations for:

1. **Disko** - For declarative disk partitioning and formatting
2. **Impermanence** - For ephemeral root filesystem with persistence where needed
3. **rEFInd** - Boot manager replacement for systemd-boot

## Setup Instructions

### Preparation

1. Back up all important data before testing
2. Create bootable USB with:
   ```bash
   sudo dd if=nixos-proart-test.iso of=/dev/sdX bs=4M status=progress
   ```
3. Boot from the USB drive

### Testing Disko

To test the Disko configuration without applying changes:

```bash
test-disko --dry-run
```

To apply the Disko configuration to a specific device:

```bash
test-disko --target /dev/nvme0n1
```

### Testing Impermanence

After setting up the disk with Disko, you can test the impermanence configuration:

```bash
# Mount the root and persist partitions
mount -o subvol=root /dev/nvme0n1p3 /mnt
mkdir -p /mnt/persist
mount -o subvol=persist /dev/nvme0n1p3 /mnt/persist

# Create a test file in persist
echo "This should persist" > /mnt/persist/test.txt

# Simulate a reboot with impermanence
umount /mnt/persist
umount /mnt
mount -o subvol=root /dev/nvme0n1p3 /mnt

# Wipe the root subvolume
btrfs subvolume delete /mnt/root
btrfs subvolume create /mnt/root
umount /mnt
mount -o subvol=root /dev/nvme0n1p3 /mnt

# Remount persist and verify test.txt still exists
mkdir -p /mnt/persist
mount -o subvol=persist /dev/nvme0n1p3 /mnt/persist
cat /mnt/persist/test.txt  # Should output "This should persist"
```

### Testing rEFInd

To test rEFInd after Disko setup:

```bash
# Install rEFInd to the ESP
mount /dev/nvme0n1p1 /boot
refind-install --usedefault /dev/nvme0n1p1

# Create test entries
mkdir -p /boot/EFI/nixos
cp /run/current-system/kernel /boot/EFI/nixos/bzImage.efi
cp /run/current-system/initrd /boot/EFI/nixos/initrd.efi
```

## Backup and Recovery

The ISO includes tools for backing up your home directory:

```bash
# Mount external USB drive
mount /dev/sdX1 /mnt/backup

# Backup home directory
rsync -aAXv --exclude={"/home/b7r6/.cache/*","/home/b7r6/Downloads/*"} /home/b7r6/ /mnt/backup/home/
```

## Hardware Support

The ISO includes drivers for:
- NVIDIA RTX 4060 GPU
- AMD Radeon 890M GPU
- Intel Wi-Fi
- NVMe SSDs
- All standard ProArt P16 peripherals

## Next Steps

After testing is successful, enable the modules in your system configuration:

1. Uncomment the imports in `configuration/system.nix`
2. Enable the rEFInd configuration
3. Re-run the NixOS rebuild
4. Enjoy your declarative, impermanent, and reproducible system! 