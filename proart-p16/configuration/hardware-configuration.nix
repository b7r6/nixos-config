# Hardware configuration for ASUS ProArt P16
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # =====================================================
  # ASUS ProArt P16 specific configuration
  # =====================================================

  # Use latest kernel for better Zen 5 and RDNA 3 support
  # From research, kernel 6.14+ is required, 6.15+ recommended
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Kernel parameters for better power management
  boot.kernelParams = [
    "amd_pstate=active"     # Enable AMD active power management
    "amdgpu.ppfeaturemask=0xffffffff"  # Enable all amdgpu power features
    "nvidia.NVreg_PreserveVideoMemoryAllocations=1"  # Better suspend/resume
    "nvidia-drm.modeset=1"  # Enable proper modesetting
    "amdgpu.runpm=0"        # Disable runtime power management for amdgpu to avoid conflicts
  ];

  # Blacklist problematic modules
  boot.blacklistedKernelModules = [ "ucsi_acpi" "nouveau" ];

  # ASUS-specific services with better configuration
  services.supergfxd = {
    enable = true;
    settings = {
      # Set default mode for graphics switching
      # "integrated" for better battery, "hybrid" for performance when needed
      default_mode = "hybrid";
      
      # Set to "compute" if you need to disable the NVIDIA GPU entirely
      # compute_mode = "integrated"; 
      
      # Supported modes based on ASUS-Linux docs
      vfio_enable = false;  # Set to true only if you need GPU passthrough
      no_logind = false;    # Keep logind integration for proper power management
    };
  };
  
  systemd.services.supergfxd.path = [ pkgs.pciutils ];
  
  services.asusd = {
    enable = true;
    enableUserService = true;
    
    # Settings for better battery life and performance
    # These are based on latest ASUS-Linux documentation
    settings = {
      # These settings optimize for both battery and performance
      # You can find more details at https://asus-linux.org/
      fan_curves = true;        # Enable custom fan curves
      power_profiles = true;    # Enable power profiles management
      
      # Set charge limit to prolong battery lifespan
      battery = {
        charge_limit = 85;      # Keep battery at 85% to reduce wear
      };
    };
  };

  # Hardware acceleration and graphics support
  hardware.graphics.enable = true;
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    # Enable Vulkan support for both AMD and NVIDIA
    extraPackages = with pkgs; [
      amdvlk
      vulkan-loader
      vulkan-validation-layers
      libva       # VA-API support
      libva-utils # VA-API utilities
      vaapiVdpau  # VDPAU backend for VA-API
    ];
  };

  # NVIDIA configuration optimized for this hardware
  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement = {
      enable = true;         # Enable power management features
      finegrained = true;    # Enable more granular power control
    };
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    
    # Properly configure Optimus/Prime for hybrid graphics
    prime = {
      offload = {
        enable = true;       # Enable on-demand GPU usage
        enableOffloadCmd = true;
      };
      # Set AMD as primary (card0) and NVIDIA as secondary (card1) GPU
      # IMPORTANT: These IDs should match what lspci shows 
      # Use `lspci -v | grep -E 'VGA|3D'` to find the correct IDs
      amdgpuBusId = "PCI:6:0:0";  # AMD Radeon 890M
      nvidiaBusId = "PCI:1:0:0";  # NVIDIA RTX 4060
    };
  };

  services.xserver.videoDrivers = [ "amdgpu" "nvidia" ];

  # Install GPU tools and drivers
  environment.systemPackages = with pkgs; [
    cudatoolkit
    linuxPackages.nvidia_x11
    nvtop              # Monitor NVIDIA GPU usage
    radeontop          # Monitor AMD GPU usage
    powertop           # Advanced power management
    tlp                # Power management
    glxinfo            # For GPU diagnostics
    pciutils           # For hardware inspection
    
    # ASUS-Linux specific tools
    asusctl            # Control ASUS laptop features
    supergfxctl        # Control GPU switching
  ];

  # Kernel modules
  boot.kernelModules = [ "kvm-amd" "amdgpu" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.nvidia_x11 ];

  # Available kernel modules for initrd
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usbhid"
    "sdhci_pci"
    "amdgpu"          # Add amdgpu for early framebuffer
    "i2c-dev"         # Add i2c for GPU detection
  ];

  # Environment variables for optimal GPU performance
  environment.sessionVariables = {
    CUDA_PATH = "${pkgs.cudatoolkit}";
    LD_LIBRARY_PATH = "${pkgs.linuxPackages.nvidia_x11}/lib:${pkgs.cudatoolkit}/lib";
    
    # Improve AMD GPU support
    AMD_VULKAN_ICD = "RADV";
    RADV_PERFTEST = "l2"; # Improve L2 cache usage on RDNA 3
    
    # Fix screen tearing
    LIBVA_DRIVER_NAME = "radeonsi";
    
    # Set hardware acceleration for video
    MOZ_X11_EGL = "1";
    
    # Improve battery life
    ENABLE_VKBASALT = "0";
    
    # Force DRI_PRIME for integrated GPU
    DRI_PRIME = "1";
    
    # Correct card ordering for Wayland
    WLR_DRM_DEVICES = "/dev/dri/card0:/dev/dri/card1";
  };

  # Optimized power management
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      PLATFORM_PROFILE_ON_AC = "performance";
      PLATFORM_PROFILE_ON_BAT = "low-power";
      RUNTIME_PM_ON_AC = "auto";
      RUNTIME_PM_ON_BAT = "auto";
      PCIE_ASPM_ON_AC = "default";
      PCIE_ASPM_ON_BAT = "powersupersave";
    };
  };

  # You will need to adjust these based on your actual partition UUIDs
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];
  
  # Platform-specific settings
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
} 