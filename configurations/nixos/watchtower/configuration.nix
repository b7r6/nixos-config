{
  modulesPath,
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    "${modulesPath}/virtualisation/amazon-image.nix"
  ];

  # Enable IP forwarding for Tailscale subnet routing and exit node
  boot.kernel.sysctl = {
    "net.core.gro_normal_batch" = 8;
    "net.core.gro_flush_timeout" = 200000;
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

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

  # TODO[b7r6]: doesn't belong here...
  programs.nh.enable = true;

  networking = {
    hostName = "watchtower";

    firewall = {
      enable = true;

      # Tailscale needs these ports
      allowedUDPPorts = [ config.services.tailscale.port ];
      checkReversePath = "loose";
    };
  };

  services.tailscale = {
    enable = true;

    extraUpFlags = [
      "--accept-dns"
      "--accept-routes"
      "--ssh"
    ];
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      AllowAgentForwarding = true;
    };
  };

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" ];
  };

  # Enable SSH agent
  programs.ssh.startAgent = true;

  # TODO[mechanyx]: when you packer this, add more admin keys...
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

  # Set your time zone
  time.timeZone = "UTC";

  # Basic system packages
  environment.systemPackages = with pkgs; [
    alacritty
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
    omnix
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  system.stateVersion = "25.05";
}
