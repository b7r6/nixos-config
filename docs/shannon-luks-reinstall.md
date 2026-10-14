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
/home in restic→R2. The host key (agenix identity) is either carried over or
rotated + rekeyed — both paths below are tested; 2026-10-11 took the rotate
path because the old key was not recoverable.

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

**Your admin identity** (`id_ed25519_b7r6`, e.g. via Proton Drive): it pushes
the branch and, if the host key is gone, rekeys every secret. This is the
one thing you truly cannot do without.

**The host-key bundle** (~5 KB, optional): `/tmp/shannon-reinstall-bundle/` on
the old system, also in R2 at `straylight-archive/shannon-reinstall/bundle/`.
Holds shannon's `ssh_host_*` (the agenix identity) + `rclone.conf`. With it,
step 3a; without it, step 3b (≈10 min longer, no other cost). Do not spend
time scanning the installer stick for it: the ISO is dd'd over the whole
device and nothing else is on it (checked 2026-10-11).

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

# 3a. HAVE the bundle: preserved host key → agenix decrypts on first boot.
cp /path/to/bundle/ssh_host_* /mnt/etc/ssh/
chmod 600 /mnt/etc/ssh/ssh_host_*_key
ssh-keygen -y -f /mnt/etc/ssh/ssh_host_ed25519_key   # must equal secrets/keys.nix hosts.shannon

# 3b. NO bundle (what 2026-10-11 did): rotate the host key and rekey.
#     The install above already ran fine; agenix just printed
#     "identityPaths entry … not present" and skipped the secrets.
ssh-keygen -t ed25519 -N '' -C root@shannon -f /mnt/etc/ssh/ssh_host_ed25519_key
ssh-keygen -t rsa -b 4096 -N '' -C root@shannon -f /mnt/etc/ssh/ssh_host_rsa_key
cat /mnt/etc/ssh/ssh_host_ed25519_key.pub   # → paste (type + key only) into secrets/keys.nix hosts.shannon
#     Then, with id_ed25519_b7r6 in ~/.ssh (rekey-secrets passes it to agenix):
nix run --accept-flake-config ~/src/nixos-config#rekey-secrets   # 40 secrets, ~30 s
git -C ~/src/nixos-config -c user.name=b7r6 -c user.email=b7r6@b7r6.net \
  commit -am 'secrets: rotate shannon host key + rekey'
#     Re-run step 2 (incremental; ~3 min). Its log must now show
#     "decrypting … fleet-orbit-env …" instead of the agenix warning.

# 3c. Nothing on the ISO survives reboot — carry the committed tree onto the
#     new disk, OUTSIDE the restic-restored path so the restore cannot clobber
#     it (uid 1000 = b7r6 on the target; the ISO shows it as "nixos"):
mkdir -p /mnt/home/b7r6 && cp -a /home/nixos/src/nixos-config /mnt/home/b7r6/nixos-config.reinstall
chown -R 1000:100 /mnt/home/b7r6/nixos-config.reinstall
#     Push from the ISO if the admin key is present, else from there after boot.
#     Also make the journal persistent NOW, so a failed first boot leaves logs
#     (journald only persists when this directory exists):
mkdir -p /mnt/var/log/journal

# 4. Login password. The fleet is SSH-key-only (no hashes in config) and
#    pam_pwquality is enforced, so without this SDDM is a wall. root is
#    optional (b7r6 is in wheel); --no-root-passwd above left it locked.
nixos-enter --root /mnt -c 'passwd b7r6'        # ignore agenix chown noise
nixos-enter --root /mnt -c 'passwd root'        # optional

# 5. Reboot → LUKS passphrase → SDDM → b7r6.
swapoff /mnt/.swap/swapfile; reboot
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
- If `/run/agenix/fleet-orbit-env` is missing: the host key on disk is not the
  one in secrets/keys.nix — `ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key`
  must print exactly `hosts.shannon`. Fix = step 3b (rotate + rekey) and a
  rebuild; nothing else can be wrong here.

## If it does not come up

Nothing on the ISO survives a reboot (no shell history, no Claude session),
so the whole recovery path is here. The installer stick stays plugged in.

**Get back to the mounted state** (≈1 min, the install is untouched):

```sh
sudo -i
nix run github:nix-community/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1 -- \
  --mode mount --flake "github:b7r6/nixos-config/luks-reinstall#shannon-bootstrap"
journalctl -D /mnt/var/log/journal -b -1 -p warning     # the failed boot's log
```

Then by symptom:

| Symptom | Meaning | Fix |
|---|---|---|
| Firmware ignores the NVMe, boots the stick or drops to setup | BootOrder lost | pick "Linux Boot Manager" in the firmware boot menu (F2/Esc at POST), or from the ISO `efibootmgr -o <id>` where `efibootmgr -v` shows the `HD(1,GPT,…)\EFI\systemd\systemd-bootx64.efi` entry |
| systemd-boot menu shows, kernel hangs/panics before any prompt | initrd | in the menu pick the previous generation (same kernel; gen 3 = same initrd minus aesni_intel). Read the journal above. |
| Passphrase prompt rejects the passphrase | typo/layout (keymap is `us`) | from the ISO `cryptsetup open --test-passphrase /dev/nvme0n1p2`; if it is truly lost, there is no recovery — the LUKS header has one keyslot. Reinstall from step 1. |
| Unlocks, then emergency shell / root not found | fstab vs disk | `blkid /dev/mapper/cryptroot`, `btrfs subvolume list /mnt`; compare with `disko.nix`. Fix, re-run step 2. |
| SDDM appears, login fails | password / session | `Ctrl-Alt-F2`, log in on tty; `journalctl -b -u display-manager`. Password: `nixos-enter --root /mnt -c 'passwd b7r6'` from the ISO. |
| Boots, no wifi | driver/firmware (mt7925e, blobs are in the closure) | `dmesg \| grep -i mt79`; tether by USB and `nh os switch .` anyway |
| Boots, `/run/agenix` missing or empty | host key ≠ keys.nix | `ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key` vs `hosts.shannon`; step 3b |
| Boots, orbit failing | see "First-boot checks" | `journalctl -u orbit -b` |

Every fix above is "edit, commit, re-run step 2 from the ISO" (incremental,
~3 min) or a one-liner on the mounted target. There is no scenario that
needs a reformat except a lost passphrase.

## Why a lost host key is cheap

`id_ed25519_b7r6` is an admin recipient on every secret (via
secrets/admin-recipients.json), so a lost host key never loses data: step 3b
rotates the key and re-encrypts all 40 secrets in one command. Nothing else
in the repo consumes the host key (no knownHosts, no build-machine lists), so
`secrets/keys.nix` is the only edit. Other fleet hosts will see a changed
host key for shannon on their next ssh — expected.

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
