# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                  // hyper-modern-nixos // installer/aarch64-jetson-netboot
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# RAM-only netboot installer for the Jetson AGX Thor (filament). Not a USB
# image: the build products are a kernel + netboot ramdisk delivered by kexec
# from the running system (or PXE/memdisk where a real broadcast domain
# exists). Built and bundled by modules/flake/netboot.nix; playbook in
# docs/src/operations/netboot-jetson.md.
#
# Headless by design: sshd is up with the fleet admin keys as root — the box
# comes back on DHCP and the install is driven entirely over ssh
# (nixos-anywhere --phases disko,install).
#
{
  flake,
  modulesPath,
  lib,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
    flake.self.nixosModules.jetson-thor
  ];

  hardware.jetson-thor.enable = true;

  # RAM image: no bootloader — override the platform module's GRUB arrangement,
  # which only applies to on-disk installs
  boot.loader.grub.enable = lib.mkForce false;

  # ── Installer Identity ─────────────────────────────────────────────────────

  networking.hostName = "filament-netboot";

  system.nixos.tags = [
    "netboot"
    "jetson-thor"
  ];

  # ── Pruned hardware set ────────────────────────────────────────────────────

  # The all-hardware profile demands initrd modules the L4T kernel doesn't
  # build (3w-9xxx et al); this is a RAM installer for one known machine, so
  # pin the module and filesystem set instead.
  hardware.enableAllHardware = lib.mkForce false;
  boot.initrd.availableKernelModules = [ "nvme" ];
  boot.supportedFilesystems = lib.mkForce [
    "vfat"
    "ext4"
    "squashfs"
    "overlay"
  ];

  # panic=30: a failed boot self-reboots and falls through to whatever is on
  # disk instead of hanging a headless box. (For kexec delivery the cmdline is
  # supplied by the kexec kit, not these params — see netboot.nix.)
  boot.kernelParams = [
    "panic=30"
    "console=tty0"
  ];

  # ── Remote access ──────────────────────────────────────────────────────────

  services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

  # fleet_admins ssh keys, same source of truth as secret recipients
  users.users.root.openssh.authorizedKeys.keys = builtins.fromJSON (
    builtins.readFile ../../secrets/admin-recipients.json
  );

  system.stateVersion = "25.11";
}
