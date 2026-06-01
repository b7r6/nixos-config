{ config
, pkgs
, lib
, ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.nvidia;
in
{
  options.hyper-modern-nixos.nvidia.enable = mkEnableOption "hyper-modern-nixos.nvidia" // {
    default = false;
  };

  config = mkIf cfg.enable {
    # Allow unfree packages (NVIDIA drivers are proprietary)
    nixpkgs.config.allowUnfree = true;

    # Graphics configuration
    hardware.graphics = {
      enable = true;
      enable32Bit = false;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };

    # X server configuration
    services.xserver.videoDrivers = [ "nvidia" ];

    # NVIDIA specific settings
    hardware.nvidia = {
      modesetting.enable = true;
      nvidiaSettings = true;
      open = true; # RTX 5090 should work with open drivers too if you want to try

      # Use production or beta for RTX 5090 support
      package = config.boot.kernelPackages.nvidiaPackages.beta;

      powerManagement.enable = false;
      powerManagement.finegrained = false;
    };

    # CUDA is managed via nvidia-sdk containers, not nixpkgs

    # Docker with NVIDIA support (if needed)
    # virtualisation.docker.enable = true;
    # hardware.nvidia-container-toolkit.enable = true;

    # Ensure kernel modules are loaded
    boot.kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_uvm"
      "nvidia_drm"
    ];

    boot.blacklistedKernelModules = [ "nouveau" ];

    # May be needed for some applications
    boot.extraModprobeConfig = ''
      options nvidia-drm modeset=1
    '';
  };
}
