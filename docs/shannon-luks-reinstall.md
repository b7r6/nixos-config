# shannon → encrypted reinstall (LUKS root)

Brings shannon back **identical but encrypted**, in two stages:

1. **`shannon-bootstrap`** — the same host with `hyper-modern-nixos.profile =
   "bootstrap"`: desktop, shell, terminal, Emacs, tailscale, fleet-orbit —
   and NOTHING that compiles from source (no nativelink, narsil, wintermute,
   VS Code, cloud CLIs). Every store path comes from cache.nixos.org /
   nix-community. Installs from the stock ISO in RAM in well under an hour.
2. **`shannon`** — the full profile, switched to FROM the installed system,
   where there is disk, swap and time. This is the one that builds the forks.

Config + inputs on GitHub (PUBLIC — no token needed, verified 2026-10-08),
/home in restic→R2, host key preserved (unlocks the secrets).

## Why two stages (read once, then never hang the box again)

`disko-install` builds the ENTIRE closure in the installer's `/nix/store`,
which on the ISO is a **16 GiB tmpfs in RAM**, with **no swap**, and only then
touches the disk. The full shannon closure is ~29 GiB unpacked before a single
compile starts; with 24 threads of from-source Rust/Haskell/Lean on top, the
box exhausts RAM and locks up silently — no fans, no OOM message. That was
every failed attempt in 2026-10. The maintainers have declined to change it
(disko #942/#1209/#1138).

`nixos-install --root /mnt`, by contrast, builds **in the target store**
(`nix build --store /mnt`): downloads stream onto the NVMe, compile scratch is
`/mnt/nix/var/nix/builds`, and the disko layout now carries a 32 GiB swapfile
inside the LUKS container that is live before the build starts. Parallelism
is bounded because this is a 13" chassis (see `hardware-configuration.nix`).

## Carry to the installer (phone / 2nd stick)

**The host-key bundle** (~5 KB): `/tmp/shannon-reinstall-bundle/` on the old
system, also in R2 at `straylight-archive/shannon-reinstall/bundle/`. It holds
shannon's `ssh_host_*` (the agenix identity) + `rclone.conf` (R2 access for
restic). Without it, see FALLBACK.

## USB

NixOS graphical installer, same nixpkgs rev as the flake (26.11 / e7439b6 —
so every nixpkgs path the install needs is already a Hydra build). Boot it,
get network, open a terminal.

## Install (on the ISO)

```sh
sudo -i

# 0. If the branch is not pushed yet, use the local checkout instead of the
#    github: URL below (both forms work; the local tree must be committed):
#    FLAKE=/home/nixos/src/nixos-config
FLAKE=github:b7r6/nixos-config/luks-reinstall

# 1. Partition + LUKS (passphrase prompt — this becomes the boot passphrase)
#    + btrfs @ /@home /@swap + 32G swapfile, all mounted under /mnt.
#    disko rev pinned to the one in flake.lock.
nix run github:nix-community/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1 -- \
  --mode destroy,format,mount --flake "$FLAKE#shannon-bootstrap"

mount | grep ' /mnt'      # expect /mnt, /mnt/home, /mnt/.swap, /mnt/boot
swapon --show             # expect /mnt/.swap/swapfile 32G active
#   if it is not:  swapon /mnt/.swap/swapfile

# 2. Install the BOOTSTRAP profile, building in the TARGET store.
#    --max-jobs 2 --cores 8: bounded for RAM and for the chassis.
#    accept-flake-config: picks up nix-community + supabase caches from flake.nix.
nixos-install --root /mnt \
  --flake "$FLAKE#shannon-bootstrap" \
  --no-root-passwd --no-channel-copy \
  --max-jobs 2 --cores 8 \
  --option accept-flake-config true

# 3. Preserved host key → agenix decrypts on first boot (NO rekey needed).
cp /path/to/bundle/ssh_host_* /mnt/etc/ssh/
chmod 600 /mnt/etc/ssh/ssh_host_*_key

# 3b. Installing from the LOCAL checkout (unpushed)? Nothing on the ISO
#     survives reboot — carry the committed tree onto the new disk, OUTSIDE
#     the restic-restored path so the restore cannot clobber it:
mkdir -p /mnt/home/b7r6 && cp -a /home/nixos/src/nixos-config /mnt/home/b7r6/nixos-config.reinstall
nixos-enter --root /mnt -c 'chown -R b7r6: /home/b7r6/nixos-config.reinstall'
#     After first boot: push it (`git push origin luks-reinstall`) from there.

# 4. Login password. The fleet is SSH-key-only (no hashes in config) and
#    pam_pwquality is enforced, so without this SDDM is a wall.
nixos-enter --root /mnt -c 'passwd b7r6'

# 5. Reboot → LUKS passphrase → SDDM → b7r6.
reboot
```

If step 2 dies, re-run it: everything already in `/mnt/nix/store` is reused.
Watch memory from a second terminal with `free -g`; the swapfile should be
mostly idle at 2×8.

## First boot (bootstrap profile, encrypted)

```sh
# a. /home from R2. The restic timer is DISABLED in the bootstrap profile, so
#    `latest` is still the pre-reinstall snapshot — restore BEFORE switching
#    to the full profile (which re-enables the hourly timer).
sudo restic-system snapshots          # sanity: newest should be the old box
sudo restic-system restore latest --target /

# b. Flip to the full profile. `nh os switch .` resolves the hostname →
#    `.#shannon` = full. This is the long one (narsil, wintermute, nativelink
#    client, elisp): bounded to 4×8 by configuration.nix, with 32G swap + zram.
cd ~/src/nixos-config && git pull
nh os switch .            # or: sudo nixos-rebuild switch --flake .#shannon
```


## First-boot checks: fleet-orbit (the reason for all of this)

```sh
systemctl status orbit --no-pager          # active (running); ExecStartPre seeded /var/lib/orbit
ls -la /run/agenix/fleet-orbit-env         # exists, root 0400 → the host key decrypted it
ls /var/lib/orbit/bin/                     # orbit/ … and, after the TUF pull, osqueryd/ (+ desktop/)
journalctl -u orbit -b --no-pager | grep -iE 'enroll|error|certificate|update' | tail -20
#   expect: "enrolled" / osqueryd started; NO "certificate verify failed" and
#   NO "no such file or directory" on osqueryd (that would be nix-ld)
```

- Secureframe → Device Management: shannon's record (the --specified_identifier
  triple) shows a fresh check-in and `disk_encryption: 1` (osquery reads the
  dm-crypt root).
- If `/run/agenix/fleet-orbit-env` is missing: the injected host key is wrong or
  absent — `ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key` must print the key
  ending in `MeNJ` from secrets/keys.nix. Otherwise rekey (FALLBACK above).
## FALLBACK — no host-key bundle

Your off-machine `id_ed25519_b7r6` is a recipient on every secret:

- decrypt restic creds by hand to restore /home:
  `age -d -i id_ed25519_b7r6 restic-password.age` (and `restic-r2-env.shannon.age`)
- then rekey to the NEW host key: add it to `secrets/keys.nix`, `agenix -r`
  (decrypts with id_ed25519_b7r6, re-encrypts incl. the new key), commit+push,
  rebuild.

## After it's confirmed good

`git checkout main && git merge luks-reinstall && git push` — shannon's
committed config is now the encrypted one. `disk_encryption: 1`. Then enroll
the agent (fleet-orbit is already running in both profiles).

## Any other host

The same two-stage path works for every fleet host: `<name>-bootstrap` exists
for each entry in `configurations/default.nix` (opt out with `bootstrap =
false`). The profile lives in `modules/nixos/profile.nix` (system) and
`modules/home/profile.nix` (home); add a new from-source burden to those two
lists when you add one to the fleet.
