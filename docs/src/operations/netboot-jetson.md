# Jetson netboot & re-image

How `filament` (NVIDIA Jetson AGX Thor Developer Kit, JetPack 7 / L4T 38.x) gets
re-imaged with no hands on the box, and why the obvious paths don't work. The
machinery: `modules/flake/netboot.nix` (the kexec kit),
`configurations/installer/aarch64-jetson-netboot.nix` (the RAM installer),
`modules/nixos/jetson-thor` (the platform module),
`configurations/nixos/filament/disko.nix` (the disk layout).

Everything here was established empirically on 2026-08-06 during the migration
off the factory JetPack layout.

## The short version

```console
$ nix run .#kexec-jetson                       # box returns as filament-netboot, ~1 min
$ nix run github:nix-community/nixos-anywhere -- \
    --flake .#filament --phases disko,install \
    --extra-files ~/jetson-extra-files \
    --ssh-option UserKnownHostsFile=/dev/null --ssh-option StrictHostKeyChecking=no \
    root@filament
$ ssh root@filament reboot                     # out of RAM, into the fresh install
```

`--phases disko,install` deliberately excludes nixos-anywhere's own `kexec`
phase (its generic image is unproven on Thor) and `reboot` (verify first, then
reboot yourself). `--extra-files` carries the preserved host key — see below.

## Why kexec, and the cmdline that survives

kexec from the running L4T kernel into the same-family L4T kernel is the one
delivery mechanism that needs neither working firmware networking nor physical
access. But the stock jetpack cmdline **wedges a kexec'd kernel**: the
`earlycon=tegra_utc,...` / UART console parameters poke a UART whose clock and
state the previous kernel already changed, and the kernel dies before the
console exists. The proven line is exactly:

```
init=<netboot-toplevel>/init panic=30 console=tty0 loglevel=7 clk_ignore_unused
```

`kexec.sh` in the `netboot-jetson-kexec` bundle carries this baked in — do not
"improve" it back toward the stock cmdline. `panic=30` matters: a failed boot
self-reboots and falls through to whatever is on disk, so a headless failure
costs a retry, not a road trip.

## Why not PXE (the post-mortem)

Two independent kills, both verified:

1. **The firmware cannot drive the RJ45.** The devkit's copper port is a
   Realtek RTL8126 (5GbE). NVIDIA's EDK2 enumerates it — it dutifully creates
   `UEFI PXEv4 (MAC:...)` boot entries, and `BootOrder` even tries PXE first —
   but no packet ever leaves the port: not from firmware PXE across multiple
   boot cycles, not from iPXE `snp.efi` (no usable SNP instance). The four
   `mgbe` 10G/QSFP lanes are what the firmware can actually drive, and nothing
   is cabled to them. Symptom of this class of failure: total silence — no
   DHCPDISCOVER anywhere, nothing to debug.

2. **The switch fabric eats broadcasts between segments.** Verified with a
   listener test (`socket.SO_BROADCAST` sender on the jetson, listeners
   elsewhere): unicast flows everywhere, broadcast crosses to nobody — so even
   a healthy PXE client would never find a proxyDHCP server on another segment.
   The December 2025 setup (pixiecore + GRUB-memdisk on ultraviolence,
   `uv/b7r6/basic-temporary-pxe-boot-for-jetson` on the filament repo) worked
   only because it had a dedicated private wire (`192.168.4.x` on a second
   NIC), which no longer exists.

Diagnostic recipe for next time, before building anything: send a UDP broadcast
from the target's segment and listen on the server's — if it doesn't arrive,
stop designing PXE flows.

## The memdisk trick (kept loaded)

`nix build .#netboot-jetson-memdisk` produces a single `bootaa64.efi` with
GRUB, kernel, and initrd embedded via memdisk. Whatever manages to load that
one file — firmware TFTP on a real broadcast domain, UEFI HTTP boot with a
static URI, a USB stick's `EFI/BOOT/` — boots the full installer with **zero
network needed after the transfer**. This is the December design, generalized;
it pairs with a private wire and dnsmasq if PXE is ever wanted again.

## Host-key doctrine (zero secrets churn)

The re-image preserves `/etc/ssh/ssh_host_ed25519_key` across the wipe, so the
box decrypts its agenix secrets and answers ssh with no changed-key warnings —
as if nothing happened. Before any `mkfs`: rescue the key (from the running
system, or the mounted old root), stage it as an `--extra-files` tree
(`etc/ssh/ssh_host_ed25519_key{,.pub}`, dirs 0755, key 0600), and let
nixos-anywhere place it before first boot. A verified copy for filament lives
at `b7r6@shimmer:~/.ssh/rescued-filament/`, staged at `~/jetson-extra-files/`.
Fallback if the key is lost: boot anyway, read the fresh pubkey, update
`secrets/keys.nix`, rekey, redeploy — the box is just off the tailnet until
then.

## The disk, and why wiping it is safe

The Thor's boot chain lives in QSPI, not on the NVMe: the factory GPT contains
no bootloader partitions, and the box boots via the generic removable-media
path (`\EFI\BOOT\BOOTAA64.EFI` on the ESP). The factory 16-partition layout
(`APP` = stock Ubuntu, `A_kernel`/`recovery`/`esp_alt` = fallbacks *into* that
Ubuntu) is dead weight once Ubuntu goes; `filament/disko.nix` replaces it with
1G ESP (GPT name kept as `esp` for capsule-update convention) + one ext4 root.
A byte-exact archive of the factory layout (sfdisk dump + p2–p15 images, 85M)
lives at `b7r6@shimmer:~/jetson-factory-backup/`; recovery-mode reflash from an
x86 host remains the unconditional backstop.

## Assorted sharp edges

- The old install's `systemctl reboot` can silently no-op when systemd is
  degraded; `echo b > /proc/sysrq-trigger` is the reliable lever (the disk is
  about to be wiped anyway).
- The installer (and any freshly powered Jetson) boots with a 1970 clock — TLS
  is broken until NTP syncs. Every transfer in this flow is plain ssh from the
  build host for exactly that reason.
- `nvpmodel` wants an interactive prompt on first run; if `nvfancontrol` sulks
  after a re-image, run `sudo nvpmodel -m 1` once.
- `nvidia-smi` needs root on Jetson unless the user is in the video group.
