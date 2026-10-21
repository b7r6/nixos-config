# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // azure
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Azure VM platform bits for a headless fleet node (gated). The cloud half of
# nixpkgs' virtualisation/azure-common.nix WITHOUT waagent/cloud-init: those
# want to own hostname + networking (networkd), which this fleet already owns
# (registry → NetworkManager, tailscale enrollment from agenix). Installed with
# nixos-anywhere onto a stock gen2 Ubuntu VM (sh/azure-soak.sh), kept in line
# with deploy-fleet like every other same-arch host.
#
#   - Hyper-V guest: vmbus/netvsc/storvsc in the initrd, hyperv-daemons.
#   - Accelerated networking: the Mellanox VF is a kernel-side bond slave of
#     netvsc; userspace must leave it alone (unmanaged in NetworkManager).
#   - Serial console on ttyS0 (`az serial-console connect`).
#   - UEFI gen2 firmware boots the removable path, so systemd-boot installs
#     without touching EFI variables.
#   - Headless: no display manager, no R2 FUSE mounts, no local nix cache (the
#     VMs never build; closures arrive from the builder over the tailnet).
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.azure;
  mlxDrivers = [
    "mlx4_en"
    "mlx4_core"
    "mlx5_core"
  ];
in
{
  options.hyper-modern-nixos.azure = {
    enable = lib.mkEnableOption "Azure VM platform (Hyper-V guest, serial console, headless fleet node)";

    acceleratedNetworking = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The NIC was created with accelerated networking (Mellanox SR-IOV VF).";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── Hyper-V guest ─────────────────────────────────────────────────────────
    virtualisation.hypervGuest.enable = true;

    boot.initrd.kernelModules = [
      "hv_vmbus"
      "hv_netvsc"
      "hv_utils"
      "hv_storvsc"
    ];
    boot.initrd.availableKernelModules = [
      "sd_mod"
      "sr_mod"
    ]
    ++ lib.optionals cfg.acceleratedNetworking mlxDrivers;

    boot.kernelParams = [
      "console=ttyS0,115200"
      "earlyprintk=ttyS0"
      "rootdelay=300"
    ];

    # ── Boot ──────────────────────────────────────────────────────────────────
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.configurationLimit = 10;
    boot.loader.efi.canTouchEfiVariables = false; # gen2 firmware boots EFI/BOOT/BOOTX64.EFI
    boot.loader.timeout = 2;

    # ── Networking ────────────────────────────────────────────────────────────
    # NetworkManager (fleet default) drives the synthetic netvsc NIC over DHCP;
    # the SR-IOV VF underneath is kernel-managed and must stay unmanaged.
    networking.usePredictableInterfaceNames = false;
    networking.networkmanager.unmanaged = lib.mkIf cfg.acceleratedNetworking (
      map (drv: "driver:${drv}") mlxDrivers
    );

    # Data disks by LUN, same rule as azure-common.nix.
    services.udev.extraRules = lib.concatMapStrings (i: ''
      ENV{DEVTYPE}=="disk", KERNEL!="sda" SUBSYSTEM=="block", SUBSYSTEMS=="scsi", KERNELS=="?:0:0:${toString i}", ATTR{removable}=="0", SYMLINK+="disk/by-lun/${toString i}"
    '') (lib.range 1 15);

    # ── Headless fleet node ───────────────────────────────────────────────────
    services.displayManager.sddm.enable = lib.mkForce false;
    # No per-user home-manager: the desktop home config is ~36 GiB of closure
    # the VM never uses, and the builder's uplink is a laptop's. Accounts +
    # ssh keys still come from the registry.
    hyper-modern-nixos.identity.homeManager = false;
    hyper-modern-nixos.rcloneMount.enable = lib.mkForce false;
    hyper-modern-nixos.nativelink.nixCache.enable = lib.mkForce false;
    hyper-modern-nixos.nativelink.nixCache.watchStore = lib.mkForce false;

    # A real /bin/true. REAPI actions name their binary by absolute path —
    # rechaos's execution scenarios run `/bin/true` — and a NixOS worker has
    # only /bin/sh, so every such action exited 127 (11.7k on one node in a
    # day) while "completing". fhs-bin.nix has the why (and why not envfs); it
    # defaults on with NativeLink, forced here because the soak depends on it.
    # n.b. not hermetic, and not meant to be: the soak measures the server, not
    # the toolchain contract.
    hyper-modern-nixos.fhsBin.enable = true;

    zramSwap.enable = lib.mkDefault true;
    time.timeZone = lib.mkDefault "UTC";

    environment.systemPackages = [
      pkgs.sg3_utils
      pkgs.cryptsetup
    ];
  };
}
