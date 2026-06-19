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
  options.hyper-modern-nixos.nvidia = {
    enable = mkEnableOption "hyper-modern-nixos.nvidia" // {
      default = false;
    };

    open = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use the open-source NVIDIA kernel modules. Default true: on the
        fleet's kernel (linuxPackages_testing, 7.1) the open modules are the
        verified-building path on current (Blackwell-class) SKUs. Flip false
        per-host if a host's GPU/driver needs the proprietary modules.
      '';
    };

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      defaultText = literalExpression "config.boot.kernelPackages.nvidiaPackages.latest";
      description = ''
        NVIDIA driver package. Defaults to the `latest` branch (610.x), which
        is the version that builds against the fleet's 7.1 kernel — the beta
        branch (595.x) does not (kernel dropped linux/of_gpio.h).
      '';
    };
  };

  config = mkIf cfg.enable {
    # Allow unfree packages (NVIDIA drivers are proprietary)
    nixpkgs.config.allowUnfree = true;

    # Fleet uniformity: NVIDIA hosts (near-identical SKUs) all run the 7.1
    # testing kernel for recent-motherboard bluetooth/wifi support, paired with
    # the 610.x driver above. mkDefault so a host with different hardware can
    # still override. (AMD-only hosts like watchtower don't import this module
    # and keep the stock kernel.)
    boot.kernelPackages = mkDefault pkgs.linuxPackages_testing;

    # Graphics configuration
    hardware.graphics = {
      enable = true;
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
      inherit (cfg) open;

      # latest (610.x) by default — builds against the fleet's 7.1 kernel;
      # override per-host via hyper-modern-nixos.nvidia.package.
      package =
        if cfg.package != null then cfg.package else config.boot.kernelPackages.nvidiaPackages.latest;

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
