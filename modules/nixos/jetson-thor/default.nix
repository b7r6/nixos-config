# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // jetson-thor
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# NVIDIA Jetson AGX Thor platform (JetPack 7 / L4T 38.x via anduril/jetpack-nixos).
#
# Platform constraints this module encodes (verified on filament, 2026-08-06):
#   - the boot chain lives in QSPI; the NVMe only needs an ESP. GRUB installs
#     as removable media (\EFI\BOOT\BOOTAA64.EFI) and never touches EFI vars —
#     the Jetson firmware's variable store is not to be trusted with writes
#   - wrong som/carrierBoard values cause EL3 exceptions at boot; the defaults
#     below are the AGX Thor Developer Kit and should not be improvised
#   - nixpkgs CUDA stays OFF: JetPack ships its own CUDA userspace
#   - nvpmodel demands an interactive prompt on first run; it must not be
#     wanted by anything (run `nvpmodel -m 1` once by hand if nvfancontrol
#     complains)
#
{
  config,
  lib,
  flake,
  ...
}:
let
  cfg = config.hardware.jetson-thor;
in
{
  imports = [ flake.inputs.jetpack-nixos.nixosModules.default ];

  options.hardware.jetson-thor = {
    enable = lib.mkEnableOption "NVIDIA Jetson AGX Thor platform (JetPack 7)";

    som = lib.mkOption {
      type = lib.types.str;
      default = "thor-agx";
      description = "System-on-Module type";
    };

    carrierBoard = lib.mkOption {
      type = lib.types.str;
      default = "devkit";
      description = "Carrier board type";
    };

    majorVersion = lib.mkOption {
      type = lib.types.str;
      default = "7";
      description = "JetPack major version";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.nvidia-jetpack = {
      enable = true;
      inherit (cfg) som carrierBoard majorVersion;
    };

    hardware.graphics.enable = true;

    # ── Bootloader: GRUB as removable media, EFI vars untouched ──────────────

    boot.loader = {
      systemd-boot.enable = false;

      grub = {
        enable = true;
        device = "nodev";
        efiSupport = true;
        efiInstallAsRemovable = true;
        configurationLimit = 3;
      };

      efi = {
        canTouchEfiVariables = false;
        efiSysMountPoint = "/boot/efi";
      };
    };

    # ── JetPack platform quirks ──────────────────────────────────────────────

    systemd.services.nvpmodel.wantedBy = lib.mkForce [ ];

    nixpkgs.config.cudaSupport = lib.mkForce false;
    nixpkgs.config.allowUnsupportedSystem = true;
  };
}
