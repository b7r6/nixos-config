{ modulesPath
, config
, pkgs
, lib
, ...
}:
{
  imports = [
    "${modulesPath}/virtualisation/amazon-image.nix"
    ./hardware-configuration.nix
  ];

  networking.hostName = "watchtower";

  # Enable IP forwarding for Tailscale subnet routing and exit node
  boot.kernel.sysctl = {
    "net.core.gro_normal_batch" = 8;
    "net.core.gro_flush_timeout" = 200000;
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  boot.kernelParams = [
    "intel_pstate=disable"
    "processor.max_cstate=1"
    "intel_idle.max_cstate=1"
    "idle=poll"
  ];

  powerManagement.cpuFreqGovernor = "performance";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 2222 ];

    allowedUDPPorts = [ config.services.tailscale.port ];
    checkReversePath = "loose";
  };

  services.openssh = {
    enable = true;
    ports = [ 22 2222 ];

    settings = {
      AllowAgentForwarding = true;
      MaxStartups = "100:30:200";
      TCPKeepAlive = true;
      ClientAliveInterval = 30;
      ClientAliveCountMax = 6;
    };
  };

  services.tailscale = {
    enable = true;
    port = 41641;

    extraUpFlags = [
      "--accept-dns"
      "--accept-routes"
      "--advertise-exit-node"
      "--ssh"
      "--advertise-tags=tag:ssh"
      "--advertise-tags=tag:server"
      "--hostname=watchtower"
      "--exit-node-allow-lan-access"
    ];
  };
  
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
  };

  programs.ssh.startAgent = true;

  users.users.b7r6 = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable sudo

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1ptqyz5C3YCcMgh3LUbXtjeS1rIZ5/6RHnH7D93Nqf b7r6@b7r6.net"
    ];
  };

  users.users.gedanziger = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable sudo

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICRg8xosQAO96/OOFWKuNbxEX3TnaFuacr9BQwYT7Bdp luthadel"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "UTC";

  environment.systemPackages = with pkgs; [
    btop
    cacert
    curl
    dbus
    gh
    git
    home-manager
    neovim
    ripgrep
    tmux
    wemux
    wget
    dbus
    dconf
  ];

  programs.nh.enable = true;

  nix = {
    package = pkgs.nixVersions.stable;

    extraOptions = ''
      experimental-features = nix-command flakes pipe-operators
    '';

    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "25.05";
}
