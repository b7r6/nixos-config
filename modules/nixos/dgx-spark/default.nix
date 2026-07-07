{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.hardware.dgx-spark;
  # Use linux_latest as a base for the build infrastructure, we replace the source anyway
  baseKernel = pkgs.linux_latest;
  nvidiaKernelVersion = "6.17.1";

  # Import generated NVIDIA DGX configuration
  dgxKernelConfig = import ./kernel-configs/nvidia-dgx-spark-6.17.1.nix { inherit lib; };

  nvidiaKernelBase = pkgs.linuxPackagesFor (
    baseKernel.override {
      argsOverride = rec {
        # Use the NVIDIA kernel source
        src = pkgs.fetchFromGitHub {
          owner = "NVIDIA";
          repo = "NV-Kernels";
          # From https://github.com/NVIDIA/NV-Kernels/commits/24.04_linux-nvidia-6.17-next/
          rev = "47ca203bcc5f4e1580c06fe1074d71497462ac8b";
          hash = "sha256-lPp7RFvZcPhV5v6FOxCVIB53vpNujvvP0NAW6iRaiF8=";
        };

        # Apply Rust gendwarfksyms fix patch
        kernelPatches = [
          {
            name = "rust-gendwarfksyms-fix";
            patch = ./patches/rust-gendwarfksyms-fix.patch;
          }
        ];

        version = "${nvidiaKernelVersion}-nvidia";
        modDirVersion = nvidiaKernelVersion;
        enableCommonConfig = true; # Enable NixOS defaults for dependency resolution
        ignoreConfigErrors = true; # Ignore unused config options

        # Use comprehensive NVIDIA DGX configuration with NixOS-specific overrides
        structuredExtraConfig =
          (lib.filterAttrs (
            name: _value:
            # Remove options that conflict with NixOS requirements or don't exist in this kernel
            !lib.elem name [
              "BLK_DEV_DM" # Device mapper - let NixOS handle this
              "BLK_DEV_DM_BUILTIN" # Device mapper builtin - let NixOS handle this
              "PAHOLE_VERSION" # Tool version - let NixOS handle this
              "RUSTC_LLVM_VERSION" # Compiler version - let NixOS handle this
              "RUSTC_VERSION" # Compiler version - let NixOS handle this
              "GCC_VERSION" # Compiler version - let NixOS handle this
              "LD_VERSION" # Linker version - let NixOS handle this
              "VERSION_SIGNATURE" # Version signature - let NixOS handle this
              "LOCALVERSION" # Local version - let NixOS handle this
              "LOCALVERSION_AUTO" # Local version auto - let NixOS handle this
              "INITRAMFS_SOURCE" # Initramfs source - let NixOS handle this
              "SYSTEM_TRUSTED_KEYS" # System trusted keys - debian-specific paths
              "SYSTEM_REVOCATION_KEYS" # System revocation keys - debian-specific paths
              "MODULE_SIG_KEY" # Module signing key - let NixOS handle this
              "SYSTEM_BLACKLIST_HASH_LIST" # System blacklist hash list - empty string causes build failure
              "EXTRA_FIRMWARE" # Extra firmware - empty string causes build failure
              "IPE_BOOT_POLICY" # IPE boot policy - empty string causes build failure
              "USB_STORAGE" # USB storage - ensure built-in for USB boot
              "USB_UAS" # USB Attached SCSI - ensure built-in for modern USB devices
              "OVERLAY_FS" # Overlay filesystem - ensure built-in for live boot
              "UEVENT_HELPER" # Legacy uevent helper - let NixOS use modern udev
            ]
          ) dgxKernelConfig)
          // (with lib.kernel; {
            # Critical NixOS security options that may need to override DGX defaults
            SECURITY_APPARMOR_BOOTPARAM_VALUE = freeform "1";
            SECURITY_APPARMOR_RESTRICT_USERNS = lib.mkForce yes; # NixOS enables AppArmor by default

            # USB storage support for USB boot
            USB_STORAGE = yes; # Build into kernel for USB boot
            USB_UAS = yes; # USB Attached SCSI for modern USB devices
            OVERLAY_FS = yes; # Overlay filesystem for live boot

            # Device management - use modern udev instead of legacy helper
            UEVENT_HELPER = no; # Disable legacy uevent helper for proper udev operation

            # Platform-specific overrides
            UBUNTU_HOST = no; # Not Ubuntu!
          });
      };
    }
  );

  # Fix the nvidia driver `allowedReferences` issue that breaks the build when a
  # non-default (NVIDIA 6.17.1) kernel is in use: the production module legitimately
  # references kernel/kernel.dev on aarch64, which the default check rejects.
  # Only consumed when `useNvidiaKernel = true`.
  nvidiaKernel = nvidiaKernelBase.extend (
    _final: prev: {
      nvidiaPackages = prev.nvidiaPackages // {
        production = prev.nvidiaPackages.production.overrideAttrs (old: {
          passthru = old.passthru // {
            mod = prev.nvidiaPackages.production.mod.overrideAttrs (_oldMod: {
              allowedReferences = [
                prev.kernel.dev
                prev.kernel
              ];
            });
          };
        });
      };
    }
  );
in
{
  options.hardware.dgx-spark = {
    enable = mkEnableOption "DGX Spark hardware support";

    useNvidiaKernel = mkOption {
      type = types.bool;
      # Default off: the 6.17.1 NVIDIA kernel is blocked on the nvidia-kernel-
      # modules allowedReferences issue (the `.extend` overlay above is the fix,
      # but it is not yet validated end-to-end). The standard kernel boots and
      # includes r8127 for the on-board 10GbE, so it is the safe default.
      default = false;
      description = "Whether to use the NVIDIA kernel instead of the standard NixOS kernel";
    };
  };

  config = mkIf cfg.enable {
    # Use the NVIDIA kernel if enabled, otherwise use latest kernel
    # NOTE: The mainline r8169 driver claims the RTL8127 PCI ID but cannot
    # actually drive the PHY. We use the out-of-tree r8127 driver instead and
    # blacklist r8169 to prevent it from binding first.
    boot.kernelPackages = if cfg.useNvidiaKernel then nvidiaKernel else pkgs.linuxPackages_latest;

    # Out-of-tree Realtek RTL8127 10GbE driver
    boot.extraModulePackages = [
      (config.boot.kernelPackages.callPackage ./r8127 { })
    ];

    boot.kernelParams = [
      # TH500 early console - REQUIRED for any output before full driver init
      "earlycon=uart,mmio32,0x16A00000"
      # Serial console at 921600 baud (TH500 UART default)
      "console=ttyS0,921600"
      # VGA console (last console= becomes /dev/console)
      "console=tty0"
      # SBSA Generic Watchdog Timer action - CRITICAL: prevents watchdog reset
      # action=1 means "set pretimeout to panic, timeout to reboot"
      # Without this, the watchdog fires and resets the system during boot
      "sbsa_gwdt.action=1"
      # Conservative PCIe settings for GB10 GPU and ConnectX-7
      "pci=pcie_bus_safe"
      # Disable memory zeroing for GPU workload performance
      "init_on_alloc=0"
      # Disable nouveau (redundant with blacklist but belt-and-suspenders)
      "nouveau.modeset=0"
      # Enable experimental framebuffer device for NVIDIA driver (needed for console)
      "nvidia-drm.fbdev=1"
      # Allow open kernel module to load on unsupported (e.g. engineering sample) GPUs
      "nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"
    ];

    # Modules to force-load early in initrd
    # These match FastOS init_prep exactly
    boot.initrd.kernelModules = [
      # SBSA Generic Watchdog - MUST load early to disarm watchdog
      "sbsa_gwdt"
      # Force load NVMe to ensure storage is available
      "nvme"
    ];

    # Modules available in initrd for TH500 platform boot
    boot.initrd.availableKernelModules = [
      # Storage (FastOS loads these first)
      "nvme"
      # USB (FastOS loads these for USB boot)
      "xhci_plat_hcd"
      "usb_storage"
      "hid"
      "usbhid"
      "hid_generic"
      "uas"
      # NVIDIA GPU (for modeset)
      "nvidia"
      "nvidia-modeset"
      "nvidia-drm"
      # ConnectX-7 networking
      "mlx5_core"
    ];

    boot.blacklistedKernelModules = [
      "nouveau" # Ensure we use the proprietary NVIDIA driver
      "r8169" # Broken for RTL8127 — use out-of-tree r8127 instead
      "coresight_etm4x" # ARM CoreSight debugging (can cause overhead on DGX)
    ];

    # Enable NVIDIA driver
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      modesetting.enable = true;
      # nvidia-open has build issues on aarch64 (wrong ELF types), so use the
      # proprietary driver which has better aarch64 support on this platform.
      open = false;
      nvidiaPersistenced = true;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidia_x11;
    };

    hardware.enableRedistributableFirmware = true;

    nixpkgs.config.allowUnfree = true;

    # CUDA is managed via nvidia-sdk containers, not nixpkgs
    # nixpkgs.config.cudaSupport = true;

    # TODO: firefox doesn't build with CUDA 13 yet (issues with cudnn-frontend and
    # onnxruntime)
    # nixpkgs.overlays = [ (import ../overlays/cuda-13.nix) ];

    # Set up podman for NVIDIA containers (use mkDefault so docker.nix can override)
    virtualisation.podman = {
      enable = lib.mkDefault true;
      dockerCompat = lib.mkDefault true;
      defaultNetwork.settings.dns_enabled = lib.mkDefault true;
    };

    hardware.nvidia-container-toolkit.enable = lib.mkDefault true;
  };
}
