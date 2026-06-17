{
  config,
  pkgs,
  lib,
  ...
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

    # GPU containers: wire the NVIDIA Container Toolkit (CDI) whenever docker is
    # also enabled on this host. This is the CURRENT, correct option — the old
    # `virtualisation.docker.enableNvidia` is deprecated and, on x86_64, asserts
    # `hardware.graphics.enable32Bit = true` (which we deliberately leave false),
    # so it would actually break the build. The toolkit's CDI path has no such
    # requirement: it generates /var/run/cdi/nvidia-container-toolkit.json and,
    # with docker >= 25, enables `features.cdi`, so both
    #   docker run --rm --device nvidia.com/gpu=all <cuda-image> nvidia-smi
    #   docker run --rm --gpus all                 <cuda-image> nvidia-smi
    # work. mkDefault mirrors the dgx-spark/podman coupling so the two paths
    # never clash. Guarded on docker.enable so we don't drag the toolkit (and
    # its implicit hardware.graphics.enable) onto a host that isn't running
    # containers.
    hardware.nvidia-container-toolkit.enable = lib.mkIf config.hyper-modern-nixos.docker.enable (
      lib.mkDefault true
    );

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
