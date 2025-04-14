# Docker configuration for the ProArt P16
{ config, lib, pkgs, ... }:

{
  options.services.docker-proart = {
    enable = lib.mkEnableOption "Enable Docker with custom configuration";
    
    # Docker daemon options
    enableNvidia = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NVIDIA GPU support in Docker";
    };
    
    enableAMD = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable AMD GPU support in Docker";
    };
    
    # Docker storage options
    storageDriver = lib.mkOption {
      type = lib.types.enum [ "overlay2" "btrfs" "zfs" "devicemapper" "aufs" ];
      default = "overlay2";
      description = "Docker storage driver to use";
      example = "btrfs";
    };
    
    # Docker compose options
    installCompose = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Docker Compose";
    };
    
    # Docker security options
    useSandbox = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Docker sandboxing features";
    };
  };

  config = lib.mkIf config.services.docker-proart.enable {
    # Docker core service
    virtualisation.docker = {
      enable = true;
      storageDriver = config.services.docker-proart.storageDriver;
      
      # Enable docker compose if requested
      enableNvidia = config.services.docker-proart.enableNvidia;
      
      # Enable rootless mode for better security (optional)
      rootless = {
        enable = config.services.docker-proart.useSandbox;
        setSocketVariable = true;
      };
      
      # Additional daemon settings
      daemon.settings = {
        ipv6 = true;
        iptables = true;
        userns-remap = lib.mkIf config.services.docker-proart.useSandbox "default";
        default-address-pools = [
          { base = "172.30.0.0/16"; size = 24; }
          { base = "172.31.0.0/16"; size = 24; }
        ];
        default-ulimits = {
          nofile = {
            Name = "nofile";
            Hard = 64000;
            Soft = 64000;
          };
        };
        dns = [ "8.8.8.8" "1.1.1.1" ];
        features = { buildkit = true; };
        experimental = true;
        log-driver = "json-file";
        log-opts = {
          max-size = "10m";
          max-file = "3";
        };
      };
    };
    
    # Install Docker Compose if enabled
    environment.systemPackages = with pkgs; lib.optionals config.services.docker-proart.installCompose [
      docker-compose
      docker-compose-language-service
      docker-buildx
      lazydocker  # Terminal UI for Docker
    ];
    
    # Configure users to be able to use Docker without sudo
    users.users.b7r6.extraGroups = [ "docker" ];
    
    # AMD GPU support for Docker
    hardware.opengl.extraPackages = lib.optionals config.services.docker-proart.enableAMD (with pkgs; [
      rocm-opencl-icd
      amdvlk
    ]);
    
    # NVIDIA GPU support for Docker
    hardware.opengl.extraPackages32 = lib.optionals config.services.docker-proart.enableNvidia (with pkgs; [
      libva
      vaapiVdpau
    ]);
    
    # Add udev rules for Docker
    services.udev.extraRules = ''
      # Allow Docker access to devices
      KERNEL=="nvidia*", RUN="${pkgs.runtimeShell} -c 'chmod -R 0666 /dev/nvidia*'"
      KERNEL=="kfd", GROUP="video", MODE="0660"
    '';
    
    # Adjust system limits for Docker
    security.pam.loginLimits = [
      { domain = "@docker"; type = "soft"; item = "nofile"; value = "64000"; }
      { domain = "@docker"; type = "hard"; item = "nofile"; value = "64000"; }
    ];
    
    # Enable IP forwarding for Docker networking
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
    };
    
    # Ensure that Docker runs after network is available
    systemd.services.docker = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
    };
  };
} 