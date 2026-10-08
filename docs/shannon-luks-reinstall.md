# shannon → encrypted reinstall (LUKS root)

Brings shannon back **identical but encrypted**. Config in flake, /home in
restic→R2, host key preserved (the agenix identity that unlocks everything).

## Before you unplug
- Config: `luks-reinstall` branch pushed (disko LUKS layout). Verified evals clean.
- /home: restic hourly → R2 (verified, incl. all Claude sessions).
- Host key: `straylight-archive/shannon-reinstall/host-keys/` (private) — the
  master agenix identity (`SHA256:IdqF…`). KEEP A PERSONAL COPY.
- Bundle for the USB: host keys + rclone.conf.

## The USB
Write the official NixOS **minimal** installer ISO to a USB (has nix+flakes).
Copy the reinstall bundle onto it (or a second stick / your phone).

## Reinstall (boot shannon from the USB, get network up)
```sh
# 1. partition(LUKS, prompts passphrase) + format + install the whole config
sudo nix --experimental-features 'nix-command flakes' \
  run github:nix-community/disko/latest#disko-install -- \
  --flake github:b7r6/nixos-config/luks-reinstall#shannon \
  --disk main /dev/nvme0n1
#    → type the LUKS passphrase when prompted (this is your boot passphrase)

# 2. inject the preserved host key so agenix can decrypt on first boot
sudo cp /path/to/bundle/ssh_host_* /mnt/etc/ssh/
sudo chmod 600 /mnt/etc/ssh/ssh_host_*_key

# 3. reboot → enter LUKS passphrase at boot → shannon comes up encrypted
sudo reboot
```

## First boot (agenix now decrypts restic-password + R2 creds)
```sh
# restore /home from restic (192G)
sudo restic-system restore latest --target /
```

## After it's confirmed good
Merge the branch: `git checkout main && git merge luks-reinstall && git push`.
Then shannon's committed config is the encrypted one. `disk_encryption: 1`.
