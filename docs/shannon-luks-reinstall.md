# shannon → encrypted reinstall (LUKS root)  [PRIVATE-REPO AWARE]

Brings shannon back **identical but encrypted**. Config + inputs on GitHub
(PRIVATE), /home in restic→R2, host key preserved (unlocks the secrets).

## Carry two small things to the installer (copy to a phone / 2nd stick NOW)
1. **The host-key bundle** (~5KB): `/tmp/shannon-reinstall-bundle/`
   (also in R2: `straylight-archive/shannon-reinstall/bundle/`). Has shannon's
   `ssh_host_*` (the agenix identity) + `rclone.conf` (R2 access for restic).
2. **A GitHub token** — a fine-grained PAT, read-only on your repos
   (`github.com/settings/tokens`). nix needs it to fetch the PRIVATE flake +
   private inputs. Or use your off-machine `id_ed25519_b7r6` for git+ssh.

## USB
Already written: NixOS graphical 25.11 installer (sda1/sda2). Boot it.

## Reinstall (boot shannon from the USB, get network, open a terminal)
```sh
# auth so nix can fetch the private config + private inputs
export NIX_CONFIG="extra-access-tokens = github.com=<YOUR_PAT>"

# 1. partition(LUKS, prompts passphrase) + format + install the whole config
sudo --preserve-env=NIX_CONFIG nix --experimental-features 'nix-command flakes' \
  run github:nix-community/disko/latest#disko-install -- \
  --flake github:b7r6/nixos-config/luks-reinstall#shannon \
  --disk main /dev/nvme0n1
#    → type your LUKS passphrase when prompted (this becomes the boot passphrase)

# 2. inject the preserved host key so agenix decrypts on first boot (NO rekey)
sudo cp /path/to/bundle/ssh_host_* /mnt/etc/ssh/ && sudo chmod 600 /mnt/etc/ssh/ssh_host_*_key

# 3. reboot → enter LUKS passphrase at boot
sudo reboot
```

## First boot (encrypted, agenix auto-decrypts via the injected host key)
```sh
sudo restic-system restore latest --target /   # restore /home (192G) from R2
```

## FALLBACK — if you don't have the host-key bundle
Your off-machine `id_ed25519_b7r6` is a recipient on every secret. You can:
- decrypt restic creds by hand to restore /home:
  `age -d -i id_ed25519_b7r6 restic-password.age`  (and restic-r2-env.shannon.age)
- then rekey to the NEW host key: add it to secrets/keys.nix, `agenix -r`
  (decrypts with id_ed25519_b7r6, re-encrypts incl. the new key), commit+push, rebuild.

## After it's confirmed good
`git checkout main && git merge luks-reinstall && git push` — shannon's committed
config is now the encrypted one. `disk_encryption: 1`. Then enroll the agent.
