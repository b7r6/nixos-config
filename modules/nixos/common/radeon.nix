{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.hyper-modern-nixos.radeon;
in
{
  options.hyper-modern-nixos.radeon = {
    enable = mkEnableOption "AMD GPU support with ROCm" // {
      default = false;
    };

    rocm.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable ROCm compute support";
    };

    strixHalo = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Strix Halo specific optimizations";
    };
  };

  config = mkIf cfg.enable {

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    hardware.opengl = {
      enable = true;
      # driSupport = true;
      driSupport32Bit = true;

      extraPackages =
        with pkgs;
        [ amdvlk ]
        ++ (optionals cfg.rocm.enable [
          rocmPackages.clr
          rocmPackages.clr.icd
          rocmPackages.rocm-runtime
          rocmPackages.rocblas
          rocmPackages.rocsparse
          rocmPackages.rocfft
          rocmPackages.rocrand
          rocmPackages.hipblas
        ]);

      extraPackages32 = with pkgs.pkgsi686Linux; [ amdvlk ];
    };

    # ROCm specific configuration
    environment.systemPackages =
      with pkgs;
      optionals cfg.rocm.enable [
        rocmPackages.rocminfo
        rocmPackages.rocm-smi
        clinfo
        vulkan-tools
        glxinfo
      ];

    systemd.tmpfiles.rules = optionals cfg.rocm.enable [
      "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
    ];

    environment.variables = mkMerge [
      (mkIf cfg.rocm.enable { ROC_ENABLE_PRE_VEGA = "1"; })

      (mkIf cfg.strixHalo { HSA_OVERRIDE_GFX_VERSION = "11.0.0"; })
    ];

    boot.kernelParams = mkMerge [
      (mkIf cfg.strixHalo [
        "amdgpu.sg_display=0"
        "amdgpu.dpm=1"
      ])
    ];
  };
}
